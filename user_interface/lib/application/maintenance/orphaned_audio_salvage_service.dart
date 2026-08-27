import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:lefture/core/services/audio_record/audio_recorder_service.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/recording_repository_drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 1回のサルベージ走査の結果。
class SalvageReport {
  const SalvageReport({
    this.scannedDirs = 0,
    this.salvaged = 0,
    this.failed = 0,
    this.skippedActiveSession = false,
  });

  /// 走査したlectureディレクトリ数。
  final int scannedDirs;

  /// アップロードジョブとして再投入できた講義数。
  final int salvaged;

  /// 再投入を試みて失敗した講義数(次回起動で再試行される)。
  final int failed;

  /// 録音セッション中だったため走査自体を見送ったか。
  final bool skippedActiveSession;

  @override
  String toString() => skippedActiveSession
      ? 'SalvageReport(skipped: recording in progress)'
      : 'SalvageReport(scanned: $scannedDirs, salvaged: $salvaged, failed: $failed)';
}

/// 「ローカルには録音があるのに、アップロードジョブが1件も作られていない講義」を
/// 拾い直して、通常のアップロードキューへ合流させる。
///
/// ★ これが必要になった経緯:
/// 保存処理([RecordingController.upload])は、
///   `_recorder.stop()` → `encodeMasterRawToM4a()` → `enqueueMasterAudioUpload()`
/// の順で進む。`stop()` の時点でオーディオセッション(iOSの`UIBackgroundModes: audio`、
/// AndroidのForeground Service)が終了するため、直後の重いFFmpegエンコード中に
/// 画面ロック・アプリ切替が起きるとOSがアプリを止めてしまう。すると
/// `enqueueMasterAudioUpload()`に到達せず、アップロードジョブが1件も作られない。
///
/// ジョブが無い以上、UploadManagerのリトライも永久に発動しない。さらに
/// `upsertLecture`はアップロードジョブの前処理としてしか呼ばれないため、
/// 講義そのものもSupabaseへ届かない。ローカルには「無題の講義」として
/// 残り続けるが、端末を再起動しても自力では復旧しない —— 保存の再実行条件
/// (`phase == RecordingPhase.paused`)が揮発性のstateだからである。
///
/// 実際にテスターの講義3件がこの状態で丸1日取り残された。ここでは
/// 端末に残っている`master_audio.raw` / `master_audio.m4a`を起点に、
/// その取り残しを起動時に自動で拾い直す。
class OrphanedAudioSalvageService {
  OrphanedAudioSalvageService(this._db, this._recorder)
      : _repo = RecordingRepositoryDrift(db: _db);

  final AppDatabase _db;
  final AudioRecorderService _recorder;
  final RecordingRepositoryDrift _repo;

  static const String _masterM4aName = 'master_audio.m4a';
  static const String _masterRawName = 'master_audio.raw';

  Future<SalvageReport> run({required String userId}) async {
    // ★ 録音セッション中は一切触らない。
    // 一時停止中の講義は`master_audio.raw`への追記が止まっているため、
    // ファイルの更新時刻だけでは「中断された保存」と区別できない。加えて
    // [AudioRecorderService.encodeMasterRawToM4a]は内部で`_closeMasterSink()`を
    // 呼ぶので、録音中に別の講義をサルベージすると進行中のIOSinkまで
    // 閉じてしまう。走査そのものを見送り、次の起動に回す。
    if (AudioRecorderService.activeLectureId != null) {
      DevLog.add(
        '⏭️ [Salvage] Recording session in progress '
        '(${AudioRecorderService.activeLectureId}), skipping this pass.',
      );
      return const SalvageReport(skippedActiveSession: true);
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final lecturesDir = Directory(p.join(docsDir.path, 'lectures'));
    if (!await lecturesDir.exists()) {
      return const SalvageReport();
    }

    var scannedDirs = 0;
    var salvaged = 0;
    var failed = 0;

    await for (final entity in lecturesDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      scannedDirs++;

      final lectureId = p.basename(entity.path);
      try {
        if (await _salvageOne(userId: userId, lectureId: lectureId, dir: entity)) {
          salvaged++;
        }
      } catch (e, st) {
        // 1件の失敗で走査全体を止めない。ジョブを作れなかっただけなので、
        // ファイルは残っており次回起動でもう一度試せる。
        failed++;
        DevLog.add('❌ [Salvage] Failed to salvage $lectureId: $e\n$st');
      }
    }

    final report = SalvageReport(
      scannedDirs: scannedDirs,
      salvaged: salvaged,
      failed: failed,
    );

    if (salvaged > 0 || failed > 0) {
      DevLog.add('🛟 [Salvage] $report');
    }
    return report;
  }

  /// 1講義分のサルベージ。再投入できたらtrue。
  Future<bool> _salvageOne({
    required String userId,
    required String lectureId,
    required Directory dir,
  }) async {
    final m4aFile = File(p.join(dir.path, _masterM4aName));
    final rawFile = File(p.join(dir.path, _masterRawName));

    final hasM4a = await m4aFile.exists();
    final hasRaw = await rawFile.exists();
    if (!hasM4a && !hasRaw) return false;

    // 対応するローカルLecture行を探す。
    // 別アカウントの残骸や、Discardで物理削除済みの講義はここで除外される。
    final lecture = await (_db.select(_db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();

    if (lecture == null) {
      DevLog.add('⏭️ [Salvage] $lectureId: no local lecture row, leaving files alone.');
      return false;
    }
    if (lecture.deletedAt != null) {
      // 削除済み講義を勝手に復活させない(30日後にRetentionが実体ごと掃除する)。
      return false;
    }

    // 既にmaster_audioのassetがある = 正常フローに乗っている(アップロード中/
    // リトライ中/完了済み)。ここで二重にジョブを作らない。
    final assets = await _db.getAssetsForLecture(lectureId);
    if (assets.any((a) => a.type == 'master_audio')) return false;

    // 実体を用意する。
    // ★ rawがあれば常にそちらを優先してエンコードし直す(m4aが既にあっても
    // 上書きする)。rawは`encodeMasterRawToM4a`がエンコードに成功した時にしか
    // 削除されないため、両方存在する場合は「エンコード処理の途中でアプリが
    // Killされた」ケースを意味しうる。M4A(MP4)はファイル末尾に索引(moov atom)
    // を書く形式なので、書きかけのm4aは非0バイトでも再生・デコード不能なことが
    // 多い。生PCMは末尾が欠けても途中までは確実に読めるため、常にこちらを
    // 信頼できる実体として扱う。m4aしか無い(raw不在)場合に限り、過去に
    // エンコードが成功済み(rawは成功時にのみ削除される)とみなしてそのまま使う。
    final String localPath;
    if (hasRaw) {
      DevLog.add('🛟 [Salvage] $lectureId: re-encoding master audio from raw PCM...');
      localPath = await _recorder.encodeMasterRawToM4a(lectureId);
    } else {
      localPath = m4aFile.path;
    }

    // 中身が空のファイルを送っても分析は失敗するだけなので、ジョブにしない。
    if (await File(localPath).length() == 0) {
      DevLog.add('⏭️ [Salvage] $lectureId: master audio is empty, skipping.');
      return false;
    }

    // 「保存が中断された」痕跡は expectedChunks が未確定(null)であること。
    // ★ チャンクが1件も無い場合に限り、マスター音声ベースの分析へ倒す。
    // Realtime Transcribe OFF の録音がこれに該当し(チャンクを一切作らない)、
    // 今回テスターが踏んだのもこのケース。マスター音声は録音全体を含んでいる
    // ので、expectedChunks=0 で TRANSCRIBE_MASTER に流せば欠落の無い
    // 文字起こしが得られる。isRealtime=false にしておくと、マスター音声の
    // 送信完了時にUploadManagerが分析開始まで自動で繋いでくれる。
    //
    // 逆にチャンクが存在する講義(Realtime ON)は、チャンク側のジョブが既に
    // lectureのupsertを担っているため、この不具合では取り残されない。
    // 分析経路にも手を出さず、マスター音声の再投入(再生用のaudio_path)だけ行う。
    final chunkAssets = assets.where((a) => a.type == 'audio').toList();
    if (lecture.expectedChunks == null && chunkAssets.isEmpty) {
      await (_db.update(_db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.userId.equals(userId)))
          .write(
        LocalLecturesCompanion(
          expectedChunks: const Value(0),
          isRealtime: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }

    await _repo.enqueueMasterAudioUpload(
      userId: userId,
      lectureId: lectureId,
      localPath: localPath,
    );

    DevLog.add('🛟 [Salvage] $lectureId: re-queued master audio upload.');
    return true;
  }
}
