// lib/application/recording/recovery/recording_recovery_service.dart
//
// 「授業中の録音を止め忘れた/アプリがキルされた/クラッシュした」場合に
// 端末へ取り残される録音を検出し、再生できる状態まで復旧し、ユーザーが
// 選んだアクション(分析開始/削除)を実行する。
//
// 設計の要点:
// - 状態は一切永続化しない。判定は毎回「ファイルシステム + LocalUploadJobs」
//   から導出する(理由は各メソッドのコメントを参照)。
// - master_audio.rawは、分析開始またはユーザーの削除操作のどちらかが
//   確定するまで消さない。Realtime録音のテール(AudioChunkerの未flush
//   バッファ)を復元できる唯一の情報源のため。
// - エンコード(生PCM→m4a)は起動直後のバックグラウンドで自動的に始める。
//   %進捗で状態を配信するので、カードを開くタイミングに関わらず現在の
//   進捗がすぐ見える。

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lefture/application/recording/recovery/recovery_models.dart';
import 'package:lefture/application/recording/recovery/recording_finalize.dart';
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/core/services/audio_record/audio_recorder_service.dart';
import 'package:lefture/core/services/audio_record/pcm_duration_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/recording_repository_drift.dart';

class RecordingRecoveryService {
  RecordingRecoveryService({
    required RecordingRepositoryDrift repo,
    required AudioRecorderService recorder,
    required UploadManager uploadManager,
    required LectureRepositoryDrift lectureRepo,
  })  : _repo = repo,
        _recorder = recorder,
        _uploadManager = uploadManager,
        _lectureRepo = lectureRepo;

  final RecordingRepositoryDrift _repo;
  final AudioRecorderService _recorder;
  final UploadManager _uploadManager;
  final LectureRepositoryDrift _lectureRepo;

  // 今まさにRecordingControllerが録音中(録音/一時停止/保存処理中)の講義ID。
  // RecordingControllerが録音開始/終了のタイミングで
  // setActiveRecordingLectureId()を呼んで更新する。
  //
  // ★ これが無いと、アプリ起動直後の検出スキャン(app.dartから毎回自動実行
  // される)が、たまたま同時に始まった新規録音を「master_audio_uploadジョブが
  // 一度も無い」という条件だけで孤児と誤検出してしまう。誤検出されると
  // バックグラウンドエンコードがその瞬間のmaster_audio.rawのスナップショットで
  // master_audio.m4aを作ってしまい、録音自体はその後も正常に続いているのに
  // 「エンコードした瞬間で音声が切れて聴こえる」という壊れ方をする
  // (実機で確認済み — マイク自体・rawファイルへの書き込みは正常に継続していた)。
  String? _activeRecordingLectureId;

  /// RecordingControllerが録音を開始/終了する(=idle以外⇔idle)たびに呼ぶ。
  /// 録音終了時はnullを渡すこと。
  void setActiveRecordingLectureId(String? lectureId) {
    _activeRecordingLectureId = lectureId;
  }

  // lectureId -> 直近の状態。新規リスナーへ「見逃さず」現在値を配信するために
  // Streamと一緒に保持する(broadcast StreamControllerは過去の値を再送しない
  // ため、これが無いと「カードを開いた時には既にエンコード完了していた」
  // ケースで進捗0%のまま表示が固まって見える)。
  final Map<String, RecoveryEncodeState> _lastState = {};
  final StreamController<MapEntry<String, RecoveryEncodeState>> _updates =
      StreamController<MapEntry<String, RecoveryEncodeState>>.broadcast();

  void _emit(String lectureId, RecoveryEncodeState state) {
    _lastState[lectureId] = state;
    _updates.add(MapEntry(lectureId, state));
  }

  /// [lectureId]のエンコード進捗を購読する。購読開始時点の現在値を必ず
  /// 1回目に流してから、以降の更新を流し続ける。
  Stream<RecoveryEncodeState> watchEncodeState(String lectureId) async* {
    yield _lastState[lectureId] ?? RecoveryEncodeState.initial;
    yield* _updates.stream.where((e) => e.key == lectureId).map((e) => e.value);
  }

  Future<Directory> _lecturesRootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'lectures'));
  }

  /// `${docs}/lectures/*`直下のディレクトリ名(=lectureId)を列挙する。
  Future<List<String>> _listLectureDirectoryIds() async {
    final root = await _lecturesRootDir();
    if (!await root.exists()) return [];
    final ids = <String>[];
    await for (final entity in root.list()) {
      if (entity is Directory) {
        ids.add(p.basename(entity.path));
      }
    }
    return ids;
  }

  /// 起動時に呼ぶ検出処理。取り残された録音を全て見つけ、DB行が失われている
  /// ものは最小限のdraft行を再生成した上で返す。
  ///
  /// 判定条件(1つでも満たせば孤児): master_audio.rawまたはmaster_audio.m4a
  /// が存在し、かつこの講義にmaster_audio_uploadジョブが(ステータス問わず)
  /// 1件も無い。ジョブが1件でもあれば「一度は保存/確定フローを通過した」
  /// ことを意味するので、通常のアップロード中/完了後の一時ファイルとして
  /// 無視する。
  Future<List<OrphanRecording>> detectOrphans({required String userId}) async {
    final ids = await _listLectureDirectoryIds();
    DevLog.add('🔎 [Recovery] Scanning ${ids.length} lecture director(y/ies) under lectures/.');
    final orphans = <OrphanRecording>[];

    for (final lectureId in ids) {
      if (lectureId == _activeRecordingLectureId) {
        DevLog.add('🔎 [Recovery] $lectureId: currently being recorded, not an orphan.');
        continue;
      }
      try {
        final rawPath = await _recorder.getMasterRawPath(lectureId);
        final m4aPath = await _recorder.getMasterM4aPath(lectureId);
        final rawFile = File(rawPath);
        final m4aFile = File(m4aPath);
        final hasRaw = await rawFile.exists();
        final hasM4a = await m4aFile.exists();
        if (!hasRaw && !hasM4a) {
          DevLog.add('🔎 [Recovery] $lectureId: no master_audio.raw/.m4a on disk, skipping.');
          continue;
        }

        if (await _repo.hasAnyUploadJobOfKindForLecture(lectureId, 'master_audio_upload')) {
          DevLog.add('🔎 [Recovery] $lectureId: master_audio_upload job already exists, not an orphan.');
          continue;
        }

        var lecture = await _repo.getLecture(lectureId);
        if (lecture != null && lecture.userId != userId) {
          // 別アカウントの録音。今サインインしているユーザーには見せない。
          DevLog.add('🔎 [Recovery] $lectureId: belongs to a different user, skipping.');
          continue;
        }

        if (lecture != null && lecture.deletedAt != null) {
          // すでに削除(ゴミ箱)された講義の取り残しファイル。孤児として再検出・再生成しない。
          DevLog.add('🔎 [Recovery] $lectureId: lecture is deleted (soft-deleted), skipping orphan detection.');
          continue;
        }

        if (lecture == null) {
          // 通常この分岐には来ない(講義作成はマイク開始より必ず先に行われる
          // ため、rawが存在するならdraft行も存在するはず)。DB行だけが何らかの
          // 理由で失われた場合の安全網として、ファイルの更新時刻を「録音開始の
          // おおよその目安」に最小限のdraft行を再生成する。
          DevLog.add('⚠️ [Recovery] Lecture row missing for orphaned files at $lectureId. Recreating a minimal draft.');
          final approxStart = hasRaw ? await rawFile.lastModified() : await m4aFile.lastModified();
          await _repo.createDraftLecture(
            userId: userId,
            presetLectureId: lectureId,
            lectureDateTime: approxStart,
            isRealtime: false,
            autoStartAnalysis: true,
          );
          lecture = await _repo.getLecture(lectureId);
          if (lecture == null) {
            DevLog.add('⚠️ [Recovery] $lectureId: failed to recreate draft lecture row, giving up.');
            continue;
          }
        }

        final duration = await _resolveDuration(
          rawFile: hasRaw ? rawFile : null,
          m4aPath: hasM4a ? m4aPath : null,
        );

        orphans.add(OrphanRecording(
          lectureId: lectureId,
          rawPath: rawPath,
          m4aPath: m4aPath,
          hasRaw: hasRaw,
          hasM4a: hasM4a,
          duration: duration,
        ));
      } catch (e, st) {
        DevLog.add('⚠️ [Recovery] Failed to inspect lecture directory $lectureId: $e\n$st');
      }
    }

    return orphans;
  }

  /// rawがあればバイト数から厳密に、無ければm4aをffprobeして長さを求める。
  /// どちらも失敗したらDuration.zero(UIは「不明」として扱えるようDuration.zero
  /// を特別扱いしてよい)。
  Future<Duration> _resolveDuration({required File? rawFile, required String? m4aPath}) async {
    if (rawFile != null) {
      final length = await rawFile.length();
      return pcmBytesToDuration(length);
    }
    if (m4aPath != null) {
      final probed = await _recorder.probeAudioDuration(m4aPath);
      if (probed != null) return probed;
    }
    return Duration.zero;
  }

  /// 検出済みの孤児を1件エンコードする(生PCM→m4a、進捗コールバック付き)。
  /// 既にm4aが存在する(hasM4a==true)場合は再エンコードせず即座にreadyにする。
  ///
  /// [detectAndStartAll]から自動的に呼ばれるほか、失敗後の「再試行」からも
  /// 呼べるよう単体でも公開する。
  Future<void> ensureEncoded(OrphanRecording orphan) async {
    if (orphan.hasM4a) {
      _emit(orphan.lectureId, const RecoveryEncodeState(status: RecoveryEncodeStatus.ready, progress: 1.0));
      return;
    }
    if (!orphan.hasRaw) {
      // hasRaw==false かつ hasM4a==false はdetectOrphansの時点で除外済みのはず。
      _emit(
        orphan.lectureId,
        const RecoveryEncodeState(
          status: RecoveryEncodeStatus.failed,
          errorMessage: 'No audio file found.',
        ),
      );
      return;
    }

    _emit(orphan.lectureId, const RecoveryEncodeState(status: RecoveryEncodeStatus.encoding, progress: 0.0));
    try {
      await _recorder.encodeRawToM4aWithProgress(
        rawPath: orphan.rawPath,
        m4aPath: orphan.m4aPath,
        onProgress: (progress) {
          _emit(orphan.lectureId, RecoveryEncodeState(status: RecoveryEncodeStatus.encoding, progress: progress));
        },
      );
      _emit(orphan.lectureId, const RecoveryEncodeState(status: RecoveryEncodeStatus.ready, progress: 1.0));
    } catch (e) {
      DevLog.add('⚠️ [Recovery] Failed to encode orphaned recording ${orphan.lectureId}: $e');
      _emit(
        orphan.lectureId,
        RecoveryEncodeState(status: RecoveryEncodeStatus.failed, errorMessage: e.toString()),
      );
    }
  }

  /// 検出した孤児全てのエンコードを順番に(CPU負荷を分散するため並列にしない)
  /// バックグラウンドで開始する。呼び出し元はawaitせずfire-and-forgetしてよい
  /// (起動をブロックしないため)。
  Future<void> encodeAllInBackground(List<OrphanRecording> orphans) async {
    for (final orphan in orphans) {
      await ensureEncoded(orphan);
    }
  }

  /// ユーザーが「分析を開始」を選んだ時の確定処理。
  ///
  /// 事前に[ensureEncoded]が成功している(m4aが存在する)ことが前提 —
  /// UI側はRecoveryEncodeStatus.readyになるまでボタンを無効化すること。
  ///
  /// Realtime録音かつ全チャンクのendTimeが揃っていれば、master_audio.rawから
  /// テール(クラッシュで失われたAudioChunkerの未flushバッファ相当)を切り出して
  /// 最終チャンクとして送る。揃っていなければテール回収を諦め、末尾切れを
  /// 許容する(既存チャンクだけで分析する)。
  Future<void> confirmAnalysis(String lectureId) => _confirmUpload(lectureId, startAnalysis: true);

  /// ユーザーが「アップロードのみ」を選んだ時の処理。音声はサーバーへ送るが、
  /// 分析は自動発火させない — コースをまだ決めていない・クレジットを今は
  /// 使いたくない等、アップロード(ローカルファイルの安全な退避)と分析開始の
  /// タイミングを分けたいユーザー向け。以降は通常のNotStartedView(手動の
  /// Start Analysisボタン)に自然に着地する — 新しいUI状態は不要。
  Future<void> uploadOnly(String lectureId) => _confirmUpload(lectureId, startAnalysis: false);

  Future<void> _confirmUpload(String lectureId, {required bool startAnalysis}) async {
    final lecture = await _repo.getLecture(lectureId);
    if (lecture == null) {
      throw StateError('Lecture $lectureId not found. Cannot confirm upload.');
    }

    final m4aFile = File(await _recorder.getMasterM4aPath(lectureId));
    if (!await m4aFile.exists()) {
      throw StateError('Master audio for $lectureId is not encoded yet.');
    }

    // ユーザーが明示的に選んだ操作なので、autoStartAnalysisの既存設定に
    // 関わらずここで確定させる(通常のupload()と違い、これが唯一の
    // 「分析してほしいか/まだしなくていいか」の意思表示のため)。
    await _repo.updateLectureAutoStartAnalysis(
      userId: lecture.userId,
      lectureId: lectureId,
      autoStartAnalysis: startAnalysis,
    );

    String? finalChunkPath;
    double? finalChunkStartTime;
    double? finalChunkEndTime;
    int? nextChunkSequenceIndex;
    int totalChunks = 0;

    if (lecture.isRealtime == true) {
      final chunkAssets = await _repo.getChunkAssetsForLecture(lectureId);
      final tailStartSec = computeTailStartSec(chunkAssets.map((a) => a.endTime).toList());
      final rawStillExists = await File(await _recorder.getMasterRawPath(lectureId)).exists();

      if (tailStartSec == null) {
        DevLog.add(
          '⚠️ [Recovery] $lectureId: some chunk assets are missing endTime; skipping tail recovery '
          '(accepting trailing loss).',
        );
      } else if (!rawStillExists) {
        // 旧upload()経路がencodeMasterRawToM4a成功後(raw削除済み)〜DB書き込みの
        // 間で死んだケース。テールの元データが無いので諦める。
        DevLog.add('⚠️ [Recovery] $lectureId: raw audio already gone; skipping tail recovery.');
      } else {
        final tailBytes = await _recorder.readMasterRawTail(
          lectureId: lectureId,
          fromSeconds: tailStartSec,
        );
        if (tailBytes.isNotEmpty) {
          finalChunkPath = await _recorder.savePcmAsM4a(tailBytes, lectureId);
          finalChunkStartTime = tailStartSec;
          finalChunkEndTime = tailStartSec + tailBytes.length / kMasterPcmBytesPerSecond;
          nextChunkSequenceIndex = chunkAssets.length;
        }
      }

      totalChunks = finalChunkPath != null ? chunkAssets.length + 1 : chunkAssets.length;
    }

    await finalizeRecordingUpload(
      repo: _repo,
      uploadManager: _uploadManager,
      lecture: lecture,
      masterM4aPath: m4aFile.path,
      totalChunks: totalChunks,
      finalChunkPath: finalChunkPath,
      finalChunkStartTime: finalChunkStartTime,
      finalChunkEndTime: finalChunkEndTime,
      nextChunkSequenceIndex: nextChunkSequenceIndex,
    );

    // rawはもう不要(テールも既に切り出し済み)。m4aはenqueueMasterAudioUpload
    // が参照しているので、アップロード成功後にUploadManagerが削除するのを待つ
    // (ここでは触らない)。
    try {
      final rawFile = File(await _recorder.getMasterRawPath(lectureId));
      if (await rawFile.exists()) await rawFile.delete();
    } catch (e) {
      DevLog.add('⚠️ [Recovery] Failed to delete raw audio for $lectureId after confirm: $e');
    }

    _lastState.remove(lectureId);
  }

  /// ユーザーが「削除」を選んだ時の処理。ファイル本体・ジョブ・アセット行・
  /// 講義本体を全て消す(サーバーには一度も送っていないので物理削除で正しい)。
  Future<void> discard(String lectureId) async {
    // ★ サーバー側のジョブキャンセル呼び出し(cancelAndDiscardが行っている
    // ようなbest-effort呼び出し)はここでは不要。孤児の定義そのものが
    // 「master_audio_uploadジョブが一度も存在しない」＝一度もサーバーへ
    // 送信されていない、なのでキャンセルすべきサーバー側の状態が存在しえない。

    // チャンク音声(audio_chunks/*.m4a)は行を消す前にパスを控えておかないと
    // 辿れなくなる(RecordingRepositoryDrift.getLectureAssetLocalPathsと同じ理由)。
    final chunkPaths = await _repo.getLectureAssetLocalPaths(lectureId);
    for (final path in chunkPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        DevLog.add('⚠️ [Recovery] Failed to delete chunk file $path: $e');
      }
    }

    await _recorder.cleanUpMasterAudioFiles(lectureId);
    await _repo.deleteLectureJobsAndAssets(lectureId);
    await _lectureRepo.hardDeleteLecture(lectureId: lectureId);

    _lastState.remove(lectureId);
  }

  void dispose() {
    _updates.close();
  }
}
