import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:lefture/core/services/audio_record/audio_chunker.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_moment_repository_drift.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/application/asr/live_asr_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import '../credit/credit_providers.dart';
import '../profile/display_language_controller.dart';
import 'recording_language_controller.dart';
import 'recording_state.dart';
import 'upload_manager.dart';

part 'recording_controller.g.dart';

/// Realtime文字起こしを許可する最低クレジット残高(USD換算)。録音自体は
/// クレジット0でも常に可能。この制限はRealtime(継続的にサーバーへ送信し
/// 続ける処理)にのみ適用する。
const double kRealtimeMinCreditUsd = 0.1;

/// [RecordingController.setRealtimeTranscribe]の結果。失敗した理由を呼び出し側
/// (UI)へ返し、必ずユーザーに見える形で伝えられるようにするためのもの。
/// 以前は理由を`errorMessage`へ書き込んでいたが、あれは`phase == error`の
/// ときしか描画されず、トグル操作時(idle)には何も出ないまま設定だけが
/// 元に戻る——という無言の失敗になっていた。
enum RealtimeToggleResult {
  ok,

  /// 録音中は変更できない。
  lockedWhileRecording,

  /// クレジット残高が[kRealtimeMinCreditUsd]に満たない。
  insufficientCredits,
}

/// PCM16bitデータから音量振幅 (0.0 〜 1.0) を算出する
double _calculatePcmAudioLevel(Uint8List data) {
  if (data.length < 2) return 0.0;
  final byteData = ByteData.sublistView(data);
  final sampleCount = data.length ~/ 2;
  if (sampleCount == 0) return 0.0;

  double sumSquares = 0.0;
  final step = sampleCount > 512 ? sampleCount ~/ 256 : 1;
  int count = 0;

  for (int i = 0; i < sampleCount; i += step) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    final norm = sample / 32768.0;
    sumSquares += norm * norm;
    count++;
  }

  if (count == 0) return 0.0;
  final rms = math.sqrt(sumSquares / count);
  if (rms <= 0.0003) return 0.0;

  // 講義室の声に自然に反応する適度な感度ブースト
  final boosted = math.sqrt(rms) * 2.8;
  return boosted.clamp(0.0, 1.0);
}

/// コースとキーワードから Groq Whisper 用コンテキスト文字列を生成する
Future<String> _buildWhisperContext({
  required String uid,
  required String courseId,
}) async {
  final parts = <String>[];

  try {
    // 1. コースタイトルを取得
    final courseRow = await supabase
        .from('courses')
        .select('course_title, course_code')
        .eq('id', courseId)
        .eq('user_id', uid)
        .maybeSingle();

    if (courseRow != null) {
      final title = courseRow['course_title'] as String? ??
          courseRow['course_code'] as String?;
      if (title != null && title.isNotEmpty) {
        parts.add('Course: $title');
      }
    }

    // 2. 同コースの過去講義キーワードを取得（最新20件）
    final lectureRows = await supabase
        .from('lectures')
        .select('id')
        .eq('course_id', courseId)
        .eq('user_id', uid)
        .limit(10);

    final lectureIds = lectureRows.map((r) => r['id'] as String).toList();

    if (lectureIds.isNotEmpty) {
      final kwRows = await supabase
          .from('keywords')
          .select('keyword')
          .inFilter('lecture_id', lectureIds)
          .limit(20);

      final keywords =
          kwRows.map((r) => r['keyword'] as String).toSet().toList();
      if (keywords.isNotEmpty) {
        parts.add('Keywords: ${keywords.join(', ')}');
      }
    }
  } catch (e) {
    DevLog.add('[WhisperContext] Failed to fetch context: $e');
  }

  return parts.join('\n');
}

// dependencies: [] を明示することで、このproviderがdev_tools/のTestタブから
// ProviderScope(overrides: [...])で差し替え可能な「scoped provider」になる。
// 何もオーバーライドしなければ今まで通りルートの単一インスタンスとして動く。
@Riverpod(keepAlive: true, dependencies: [])
AudioRecorderService audioRecorderService(Ref ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
}

// audioRecorderServiceに依存していることを明示しないと、dev_tools/側で
// ProviderScopeを使ってaudioRecorderServiceProviderをオーバーライドしても
// このControllerには一切伝播しない(常にルートコンテナの本物のマイクを使う
// インスタンスを参照し続ける)。Riverpodの仕様上、これが必須。
@Riverpod(keepAlive: true, dependencies: [audioRecorderService])
class RecordingController extends _$RecordingController {
  StreamSubscription? _dbSubscription;
  Timer? _timer;
  AudioChunker? _chunker;
  StreamSubscription? _audioStreamSub;
  int _currentChunkIndex = 0;

  // 依存サービス
  RecordingRepositoryDrift get _repo => ref.read(recordingRepositoryDriftProvider);
  AudioRecorderService get _recorder => ref.read(audioRecorderServiceProvider);
  UploadManager get _uploadMgr => ref.read(uploadManagerProvider);
  LectureMomentRepositoryDrift get _momentRepo => ref.read(lectureMomentRepositoryDriftProvider);

  @override
  RecordingState build() {
    ref.onDispose(() {
      _dbSubscription?.cancel();
      _timer?.cancel();
    });

    // Preferences から保存済みの設定を読み込む
    final prefs = RecordingPreferences();
    return RecordingState.idle().copyWith(
      realtimeTranscribe: prefs.getRealtimeTranscribe(),
      autoStartAnalysis: prefs.getAutoStartAnalysis(),
    );
  }

  void _startWatchingLecture(String lectureId) {
    _dbSubscription?.cancel();
    _dbSubscription = _repo.watchLecture(lectureId).listen((localLecture) {
      state = state.copyWith(lecture: localLecture);
    });
  }

  // --- User Actions ---

  Future<void> toggleStartStopResume() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    // 1. Idle -> Start
    if (state.phase == RecordingPhase.idle) {
      await _startRecordingSession();
      return;
    }

    // 2. Recording -> Pause
    if (state.phase == RecordingPhase.recording) {
      await _recorder.pause();
      _timer?.cancel();

      // マイクからの音声供給が止まるだけでは、既に起動済みのオンデバイスASR
      // エンジン(モデルをロードした専用isolate)はメモリに常駐したままになって
      // しまう。一時停止中に発熱・電池消費が続く原因になるため、ここで明示的に
      // 止める(再開時に必要なら`start`し直す)。
      if (state.realtimeTranscribe) {
        await ref.read(liveAsrControllerProvider.notifier).stop();
      }

      if (state.realtimeTranscribe) {
        final flushed = _chunker?.flush();
        if (flushed != null && flushed.data.isNotEmpty) {
          final path = await _recorder.savePcmAsM4a(flushed.data, state.currentLectureId!);

          await _repo.attachAudioAndEnqueueUpload(
            userId: user.id,
            lectureId: state.currentLectureId!,
            localPath: path,
            sequenceIndex: _currentChunkIndex,
            startTime: flushed.startTimeSec,
          );
          _currentChunkIndex++;
        }
      } else {
        DevLog.add('[Pause] Realtime Transcribe is OFF, skipping chunk upload');
        _chunker?.flush(); // メモリ解放のためflushは呼ぶが結果は使わない
      }

      state = state.copyWith(phase: RecordingPhase.paused, audioLevel: 0.0);
      return;
    }

    // 3. Paused -> Resume
    if (state.phase == RecordingPhase.paused) {
      await _recorder.resume();
      _startTimer();

      if (state.realtimeTranscribe && _hasEnoughCreditsForRealtime()) {
        final recordingLanguage = ref.read(recordingLanguageControllerProvider);
        // 一時停止で止めたLiveAsrControllerは再開のたびに新しいisolateを
        // 起動し内部タイムスタンプが0から数え直しになるため、これまでの
        // 経過秒数を渡して録音全体での位置を維持する(渡さないと再開後の
        // 字幕がサーバー側watermarkフィルタで全て消えてしまう)。
        ref.read(liveAsrControllerProvider.notifier).start(
              recordingLanguage,
              initialOffsetSec: state.elapsedSeconds.toDouble(),
            );
      }

      state = state.copyWith(phase: RecordingPhase.recording);
      return;
    }
  }

  /// RecordingPageに入った瞬間に呼ぶ早期リクエスト。「授業が始まってしまった!」
  /// という時に録音開始がもたつかないよう、実際に録音ボタンを押すより前に
  /// 済ませておく。結果を待たず、UI状態(RecordingPhaseなど)にも反映しない
  /// ——実際の可否判定・エラー表示は_startRecordingSession側の既存フローに任せる。
  /// 既にpermanentlyDeniedの場合は再プロンプトしても意味が無いのでスキップする。
  Future<void> requestMicPermissionEarly() async {
    final status = await Permission.microphone.status;
    if (status.isGranted || status.isPermanentlyDenied) return;
    await Permission.microphone.request();
  }

  Future<void> _startRecordingSession() async {
    DevLog.add('[StartSession] 1/8 begin');
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    DevLog.add('[StartSession] 2/8 requesting mic/notification permissions...');
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.notification,
    ].request();
    DevLog.add('[StartSession] 3/8 permission result: $statuses');

    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Microphone permission is required.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.requestingPermission, clearErrorMessage: true);

    try {
      DevLog.add('[StartSession] 4/8 creating draft lecture...');
      final recordingLanguage = ref.read(recordingLanguageControllerProvider);
      final displayLanguage = ref.read(displayLanguageControllerProvider);
      final lectureId = await _repo.createDraftLecture(
        userId: user.id,
        presetCourseId: state.courseId,
        presetTitle: state.title.isNotEmpty ? state.title : null,
        autoStartAnalysis: state.autoStartAnalysis,
        isRealtime: state.realtimeTranscribe,
        recordingLanguage: recordingLanguage,
        displayLanguage: displayLanguage,
      );
      DevLog.add('[StartSession] 5/8 draft lecture created: $lectureId');

      // コースが選択されていればWhisperコンテキストをフェッチして保存
      final courseId = state.courseId;
      if (courseId != null) {
        final context = await _buildWhisperContext(uid: user.id, courseId: courseId);
        if (context.isNotEmpty) {
          await _repo.saveWhisperContext(lectureId: lectureId, whisperContext: context);
        }
      }

      state = state.copyWith(currentLectureId: lectureId);
      _startWatchingLecture(lectureId);

      _currentChunkIndex = 0;

      _chunker = AudioChunker(
        onChunkReady: (Uint8List chunkData, double startTimeSec) async {
          // Realtime Transcribe が Off の場合、チャンク送信をスキップ
          if (!state.realtimeTranscribe) {
            DevLog.add('[Chunker] Realtime Transcribe is OFF, skipping chunk upload for Chunk $_currentChunkIndex');
            _currentChunkIndex++;
            return;
          }

          // ★ awaitを挟む前に同期的に採番する: onChunkReadyはAudioChunkerから
          // awaitされずに呼ばれるため、チャンクが立て続けに来ると(15倍速テスト等)
          // 前のチャンクのFFmpegエンコード待ち中に次のチャンクのこのコールバックが
          // 走り出す。_currentChunkIndexの読み取り＋インクリメントがawaitの後だと、
          // 2つの異なるチャンクが同じsequenceIndexを取得してしまう競合状態になる。
          final chunkIndex = _currentChunkIndex++;
          DevLog.add('[Chunker] Chunk $chunkIndex is ready! Size: ${chunkData.length} (Start: ${startTimeSec}s)');

          final path = await _recorder.savePcmAsM4a(chunkData, lectureId);

          await _repo.attachAudioAndEnqueueUpload(
            userId: user.id,
            lectureId: lectureId,
            localPath: path,
            sequenceIndex: chunkIndex,
            startTime: startTimeSec,
          );

          _uploadMgr.tryProcessQueue();
        },
        onMasterDataReady: (Uint8List masterData) async {
          await _recorder.appendMasterRawData(masterData, lectureId);
          // マスター音声への追記と並行して、オンデバイスASRエンジンにも同じ
          // 生PCMを流し込む(Realtime Transcribe OFF、またはモデル未準備の
          // 場合はLiveAsrController側が何もしないので安全)。
          ref.read(liveAsrControllerProvider.notifier).acceptPcm16(masterData);
        },
      );

      // 設定時点ではクレジットが足りていても、録音開始までの間に別デバイス/
      // 別セッションで使い切っている可能性があるため、ここでも再確認する
      // (録音自体はブロックしない。Realtimeだけを止める)。
      // モデルが「ダウンロード中/未確認」なだけならLiveAsrController.start()側が
      // 静かにスキップしてくれる(今回のセッションだけ字幕無し)ので、ここで
      // トグルまでは触らない。明確に`failed`(この言語用のモデルが結局
      // 用意できなかった)の場合のみ、実体の無い設定として自動的にOffへ戻す。
      final modelManager = ref.read(asrModelManagerProvider.notifier);
      final modelState = modelManager.statusForLanguage(recordingLanguage);
      // 手元にモデルが無く、かつ取得にも失敗している場合だけ「実体の無い設定」
      // と見なす。オフラインでマニフェスト取得に失敗しただけ(モデルはある)なら
      // そのまま使える。
      final modelUnavailable = modelState.status == AsrModelStatus.failed && !modelState.installed;
      if (state.realtimeTranscribe && modelUnavailable) {
        DevLog.add('[StartSession] Realtime Transcribe disabled: no model available for "$recordingLanguage".');
        state = state.copyWith(realtimeTranscribe: false);
      } else if (state.realtimeTranscribe && _hasEnoughCreditsForRealtime()) {
        ref.read(liveAsrControllerProvider.notifier).start(recordingLanguage);
        // ダウンロード中/未確認のままでも録音自体はブロックしない
        // (LiveAsrController側がダウンロード完了を検知して自動的に
        // 再試行してくれるが、それまでは字幕が出ないことをここで一言
        // 知らせておく)。
        if (!modelManager.statusForLanguage(recordingLanguage).installed) {
          DevLog.add('[StartSession] ASR model still downloading for "$recordingLanguage" — captions will start once ready.');
          state = state.copyWith(
            transientNotice: 'Speech model is still downloading — live captions will start once it\'s ready.',
          );
        }
      } else if (state.realtimeTranscribe) {
        DevLog.add('[StartSession] Realtime Transcribe disabled due to insufficient credits.');
        state = state.copyWith(realtimeTranscribe: false);
      }

      DevLog.add('[StartSession] 6/8 calling _recorder.startStream()...');
      final audioStream = await _recorder.startStream();
      DevLog.add('[StartSession] 7/8 _recorder.startStream() returned, subscribing...');

      _audioStreamSub = audioStream.listen(
        (data) {
          _chunker!.processAudioStream(data);
          final level = _calculatePcmAudioLevel(data);
          state = state.copyWith(audioLevel: level);
        },
        onError: (Object e, StackTrace st) {
          DevLog.add('🔴 [StartSession] audioStream error: $e\n$st');
        },
      );

      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);
      DevLog.add('[StartSession] 8/8 recording phase active');

    } catch (e, st) {
      DevLog.add('🔴 [StartSession] failed: $e\n$st');
      // startRecordingSession()の途中でLiveAsrController.start()が既に(あるいは
      // まだ非同期で)呼ばれている可能性がある。ここでstop()しておかないと、
      // ロード済みのモデル/isolateがどこからもdisposeされないまま、
      // RecordingController/LiveAsrControllerがkeepAliveなので
      // アプリを完全に再起動するまでメモリに残り続けてしまう。
      await ref.read(liveAsrControllerProvider.notifier).stop();
      state = state.copyWith(phase: RecordingPhase.error, errorMessage: 'Failed to start: $e');
    }
  }

  /// エラー画面から復帰するための操作。録音を開始し直せる状態(idle)に戻す。
  Future<void> resetAfterError() async {
    if (state.phase != RecordingPhase.error) return;
    await ref.read(liveAsrControllerProvider.notifier).stop();
    state = state.copyWith(phase: RecordingPhase.idle, clearErrorMessage: true);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      DevLog.add('[Timer] Tick: ${state.elapsedSeconds + 1} (Phase: ${state.phase})');
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  Future<void> setAutoStartAnalysis(bool value) async {
    state = state.copyWith(autoStartAnalysis: value);
    // Preferences に保存
    await RecordingPreferences().setAutoStartAnalysis(value);

    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureAutoStartAnalysis(
        userId: lecture.userId,
        lectureId: lecture.id,
        autoStartAnalysis: value,
      );
    }
  }

  /// クレジット残高が$kRealtimeMinCreditUsd以上あるか。未取得(ロード中/
  /// オフライン等)の場合は安全側に倒してfalseを返す。
  ///
  /// 実際にサーバーへ送り始める(＝課金が発生しうる)録音開始・再開の判定用。
  /// 設定トグルの可否は[_canEnableRealtime]の方を使うこと。
  bool _hasEnoughCreditsForRealtime() {
    final summary = ref.read(creditSummaryProvider).asData?.value;
    if (summary == null) return false;
    return summary.hasAtLeastUsd(kRealtimeMinCreditUsd);
  }

  /// 設定変更のためのクレジット判定。[_hasEnoughCreditsForRealtime]と違い、
  /// 残高が未取得ならここで取得を待ち、それでも分からない(オフライン/API失敗)
  /// 場合は許可する。
  ///
  /// 「分からない=拒否」にすると、残高は足りているのに通信が済んでいないだけで
  /// トグルがONにできず、しかもユーザーには理由が分からない、という状態に
  /// なってしまうため。実際に足りない状態で録音を始めた場合は
  /// [_startRecordingSession]が改めて判定してRealtimeだけ無効化する。
  Future<bool> _canEnableRealtime() async {
    final cached = ref.read(creditSummaryProvider).asData?.value;
    if (cached != null) return cached.hasAtLeastUsd(kRealtimeMinCreditUsd);
    try {
      final summary = await ref.read(creditSummaryProvider.future);
      return summary.hasAtLeastUsd(kRealtimeMinCreditUsd);
    } catch (e, st) {
      DevLog.add('⚠️ [Realtime] credit summary unavailable, allowing the toggle anyway: $e\n$st');
      return true;
    }
  }

  Future<RealtimeToggleResult> setRealtimeTranscribe(bool value) async {
    if (state.phase != RecordingPhase.idle) {
      return RealtimeToggleResult.lockedWhileRecording;
    }

    // 録音自体は常に可能なので、ここでブロックするのはRealtimeのON操作のみ。
    if (value && !await _canEnableRealtime()) {
      return RealtimeToggleResult.insufficientCredits;
    }

    state = state.copyWith(realtimeTranscribe: value, clearErrorMessage: true);
    // Preferences に保存
    await RecordingPreferences().setRealtimeTranscribe(value);
    return RealtimeToggleResult.ok;
  }

  Future<void> addReaction(String momentType) async {
    final lectureId = state.currentLectureId;
    if (lectureId == null) return;
    await _momentRepo.addMoment(
      lectureId: lectureId,
      momentType: momentType,
      timestampSec: state.elapsedSeconds,
    );
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> addNote(String text) async {
    final lectureId = state.currentLectureId;
    if (lectureId == null) return;
    await _momentRepo.addMoment(
      lectureId: lectureId,
      momentType: 'note',
      noteText: text,
      timestampSec: state.elapsedSeconds,
    );
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> deleteMoment(String id) async {
    await _momentRepo.deleteMoment(id);
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> setTitle(String newTitle) async {
    state = state.copyWith(title: newTitle);
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureTitle(
        userId: lecture.userId,
        lectureId: lecture.id,
        title: newTitle,
      );
    }
  }

  Future<void> setCourseId(String? courseId) async {
    state = state.copyWith(
      courseId: courseId,
      forceClearCourseId: courseId == null,
    );
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureCourse(
        userId: lecture.userId,
        lectureId: lecture.id,
        courseId: courseId,
      );
    }
  }

  Future<void> upload() async {
    if (!state.canUpload) return;

    final lecture = state.lecture;
    if (lecture == null) return;

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
      await ref.read(liveAsrControllerProvider.notifier).stop();
      _timer?.cancel();

      // 1. マスター生PCMデータをAAC (M4A) に圧縮エンコード
      final masterM4aPath = await _recorder.encodeMasterRawToM4a(lecture.id);

      // 2. 最後のチャンクをフラッシュ（Realtime Transcribe が On の場合のみ）。
      // ここではまだDBに書き込まない — expectedChunksが確定してから
      // ジョブを登録する必要があるため(下記3を参照)。
      String? finalChunkPath;
      double? finalChunkStartTime;
      if (state.realtimeTranscribe) {
        final finalFlushed = _chunker?.flush();
        if (finalFlushed != null && finalFlushed.data.isNotEmpty) {
          DevLog.add('[Chunker] Final chunk is ready! Size: ${finalFlushed.data.length} bytes (Start: ${finalFlushed.startTimeSec}s)');
          finalChunkPath = await _recorder.savePcmAsM4a(finalFlushed.data, lecture.id);
          finalChunkStartTime = finalFlushed.startTimeSec;
        }
      } else {
        DevLog.add('[Upload] Realtime Transcribe is OFF, skipping final chunk upload');
        _chunker?.flush(); // メモリ解放のためflushは呼ぶが結果は使わない
      }
      final totalChunks = finalChunkPath != null ? _currentChunkIndex + 1 : _currentChunkIndex;

      // 3. expectedChunksを、最終チャンクのアップロードジョブを登録するより先に確定させる。
      // ★ 以前はこれを最後(ジョブ登録の後)に書いていたため、最終チャンクの
      // ジョブ挿入(→UploadManagerがDB監視で即座に処理を開始)がexpectedChunksの
      // コミットより先に完了してしまうことがあった。その場合UploadManagerは
      // expectedChunks==nullのまま自動分析発火の判定をスキップし、以降二度と
      // 再判定されない(=自動分析が永久に発火しない)バグがあった。
      await _repo.finishLectureRecording(
        lectureId: lecture.id,
        expectedChunks: totalChunks,
      );

      // 4. 最後のチャンクのアップロードジョブを登録
      if (finalChunkPath != null) {
        await _repo.attachAudioAndEnqueueUpload(
          userId: lecture.userId,
          lectureId: lecture.id,
          localPath: finalChunkPath,
          sequenceIndex: _currentChunkIndex,
          startTime: finalChunkStartTime!,
        );
        _currentChunkIndex++;
      }

      // 5. マスターオーディオのアップロードジョブを登録
      await _repo.enqueueMasterAudioUpload(
        userId: lecture.userId,
        lectureId: lecture.id,
        localPath: masterM4aPath,
      );

      // 6. リアルタイム収録の自動分析を、保存したこの瞬間に予約する。
      // ★ ここが無いと自動分析が永久に発火しないケースがある:
      // 最後のチャンクは「一時停止した瞬間」(toggleStartStopResumeのpause分岐)に
      // エンキューされ、多くの場合そのまま数秒で送信完了してしまう。ところが
      // expectedChunksが書かれるのはユーザーが保存を押したこの時点なので、
      // UploadManager側の「最後のチャンク完了時に発火」判定は
      // expectedChunks==nullのまま素通りし、以降その講義では二度と
      // audio_uploadジョブが完了しないため再判定される機会が無かった。
      // (保存画面で数分悩んでから保存した場合は必ずこれに該当する)
      await _maybeEnqueueStartAnalysis(lecture.id);

      state = state.copyWith(phase: RecordingPhase.queued);
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Save failed: $e'
      );
    }
  }

  /// 保存時に、リアルタイム収録の自動分析(start_analysis号砲)を予約する。
  /// 未送信チャンクが残っている場合はここでは鳴らさず、UploadManagerが
  /// 最後のチャンク完了時に鳴らす方に任せる(この時点でexpectedChunksは
  /// 既に確定済みなので、そちらの判定も正しく通るようになっている)。
  Future<void> _maybeEnqueueStartAnalysis(String lectureId) async {
    // state.lectureはwatch経由で古い可能性があるため、DBから読み直す。
    final fresh = await _repo.getLecture(lectureId);
    if (fresh == null) return;

    if (fresh.isRealtime != true) {
      // プレレコーデッドはマスター音声の送信完了時にUploadManagerが発火する。
      return;
    }
    if (fresh.autoStartAnalysis == false) {
      DevLog.add('⏸️ [Upload] 自動分析がOFFのため、号砲は鳴らしません（手動でStart Analysisが必要）。');
      return;
    }
    if (fresh.courseId == null) {
      DevLog.add('⏸️ [Upload] コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
      return;
    }

    // 二重発火ガード。保存時(ここ)と最終チャンク完了時(UploadManager)の
    // 両方が候補になるため、既に号砲があるなら何もしない。
    if (await _repo.hasStartAnalysisJobForLecture(lectureId)) {
      DevLog.add('⏭️ [Upload] start_analysisジョブが既に存在するため、二重発火を回避します。');
      return;
    }

    final pendingChunks = await _repo.getPendingChunkJobsForLecture(lectureId);
    if (pendingChunks.isNotEmpty) {
      DevLog.add(
        '⏳ [Upload] 未送信チャンクが${pendingChunks.length}件残っています。全て完了した時点でUploadManagerが分析を開始します。',
      );
      return;
    }

    final assetId = await _repo.getAnyAssetIdForLecture(lectureId);
    if (assetId == null) {
      DevLog.add('⚠️ [Upload] アセットが1件も見つからないため、号砲を鳴らせませんでした。');
      return;
    }

    DevLog.add('🎉 [Upload] 全チャンク送信済み。保存と同時に分析開始の号砲を鳴らします！');
    await _repo.enqueueStartAnalysis(
      userId: fresh.userId,
      lectureId: lectureId,
      assetId: assetId,
    );
  }

  Future<void> cancelAndDiscard() async {
    await _audioStreamSub?.cancel();
    await _recorder.stop();
    await ref.read(liveAsrControllerProvider.notifier).stop();
    _timer?.cancel();
    _dbSubscription?.cancel();

    if (state.currentLectureId != null) {
      await _recorder.cleanUpMasterAudioFiles(state.currentLectureId!);

      // ローカルのジョブ/アセットは消してこれ以上チャンクが送られないようにする
      // (Lecture本体はここでは消さない — 下のsoftDeleteLectureが読み出す必要があるため)。
      await _repo.deleteLectureJobsAndAssets(state.currentLectureId!);

      // Discard時点で、バックグラウンドのチャンクアップロード(UploadManager)が
      // 既にSupabaseへ`lectures`行を作ってしまっている可能性がある(レース)。
      // ハード削除ではなく、通常のTrash機能と同じ論理削除(deleted_at)を使う
      // ことで、Outbox経由でその行にも`deleted_at`が届くようにする。
      // 30日後には既存のリテンション処理(ローカル: LocalRetentionService /
      // サーバー: /maintenance/patrol)が自動的に完全削除する。
      await ref.read(lectureRepositoryProvider).softDeleteLecture(lectureId: state.currentLectureId!);
    }

    // `RecordingState.idle()`はrealtimeTranscribe/autoStartAnalysisを常に
    // デフォルト値(false/true)にリセットしてしまう。build()時と同様、保存済み
    // のユーザー設定を読み直さないと、Discardする度にRealtime Transcribeの
    // トグルが勝手にOffへ戻ってしまう。
    final prefs = RecordingPreferences();
    state = RecordingState.idle().copyWith(
      realtimeTranscribe: prefs.getRealtimeTranscribe(),
      autoStartAnalysis: prefs.getAutoStartAnalysis(),
    );
  }

  Future<void> uploadAudioFile(String pickedFilePath) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to upload.',
      );
      return;
    }

    if (state.courseId == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Please select a course before uploading.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      // ★ file_pickerが返すpathは、Androidでは(content://のような直接開けない
      // URIを扱えるファイルパスに変換するため)アプリのキャッシュディレクトリ
      // (.../cache/file_picker/...)を指している。キャッシュはOSが低ストレージ
      // 時などに予告無く消去できる領域で、実際にアップロードのリトライが何日も
      // 詰まっている間に消えて「二度と成功しないアップロード」になった事故が
      // あった。録音した音声(audio_recorder_service.dart)は最初から
      // getApplicationDocumentsDirectory(永続領域)に保存しているのに、
      // ファイル選択インポートだけこの一時領域に依存していたのが原因。
      // アップロードジョブに載せる前に、ここで確実に永続領域へコピーする。
      DevLog.add('[UploadAudioFile] 0/4 copying picked file to persistent storage...');
      final localFilePath = await _copyPickedFileToPersistentStorage(pickedFilePath);
      DevLog.add('[UploadAudioFile] 0/4 copied to $localFilePath');

      DevLog.add('[UploadAudioFile] 1/4 creating draft lecture...');
      final lectureId = await _repo.createDraftLecture(
        userId: user.id,
        presetCourseId: state.courseId,
        presetTitle: state.title.isNotEmpty ? state.title : null,
        autoStartAnalysis: state.autoStartAnalysis,
        isRealtime: false, // 外部ファイルは常にプレレコ
        recordingLanguage: ref.read(recordingLanguageControllerProvider),
        displayLanguage: ref.read(displayLanguageControllerProvider),
      );
      DevLog.add('[UploadAudioFile] 2/4 draft lecture created: $lectureId');

      // コースが選択されていればWhisperコンテキストをフェッチして保存
      final courseId = state.courseId;
      if (courseId != null) {
        final context = await _buildWhisperContext(uid: user.id, courseId: courseId);
        if (context.isNotEmpty) {
          await _repo.saveWhisperContext(lectureId: lectureId, whisperContext: context);
        }
      }

      DevLog.add('[UploadAudioFile] 3/4 enqueueing master audio upload...');
      await _repo.enqueueMasterAudioUpload(
        userId: user.id,
        lectureId: lectureId,
        localPath: localFilePath,
      );

      DevLog.add('[UploadAudioFile] 4/4 finishing lecture recording...');
      await _repo.finishLectureRecording(
        lectureId: lectureId,
        expectedChunks: 0, // プレレコなので expectedChunks=0
      );

      state = state.copyWith(phase: RecordingPhase.queued);
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Upload failed: $e'
      );
    }
  }

  /// file_pickerが返したpath(Androidではアプリのキャッシュ領域を指す)を、
  /// OSに予告無く消去されない永続領域(getApplicationDocumentsDirectory)へ
  /// コピーし、コピー後のpathを返す。ファイル名の衝突を避けるため
  /// タイムスタンプ+元のファイル名でリネームする。
  Future<String> _copyPickedFileToPersistentStorage(String pickedFilePath) async {
    final source = File(pickedFilePath);
    if (!await source.exists()) {
      throw Exception('Picked file not found at $pickedFilePath');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final importsDir = Directory(p.join(docsDir.path, 'imported_audio'));
    await importsDir.create(recursive: true);

    final destPath = p.join(
      importsDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_${p.basename(pickedFilePath)}',
    );
    final copied = await source.copy(destPath);
    return copied.path;
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }

  void clearTransientNotice() {
    if (state.transientNotice == null) return;
    state = state.copyWith(clearTransientNotice: true);
  }
}