import 'dart:async';
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
  if (rms <= 0.0001) return 0.0;
  // 講義室の離れた小さな教授の声でも波形が大きくアクティブに跳ねるよう感度ブースト
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
      final modelUnavailable =
          modelManager.statusForLanguage(recordingLanguage).status == AsrModelStatus.failed;
      if (state.realtimeTranscribe && modelUnavailable) {
        DevLog.add('[StartSession] Realtime Transcribe disabled: no model available for "$recordingLanguage".');
        state = state.copyWith(realtimeTranscribe: false);
      } else if (state.realtimeTranscribe && _hasEnoughCreditsForRealtime()) {
        ref.read(liveAsrControllerProvider.notifier).start(recordingLanguage);
        // ダウンロード中/未確認のままでも録音自体はブロックしない
        // (LiveAsrController側がダウンロード完了を検知して自動的に
        // 再試行してくれるが、それまでは字幕が出ないことをここで一言
        // 知らせておく)。
        if (modelManager.statusForLanguage(recordingLanguage).status != AsrModelStatus.ready) {
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
  bool _hasEnoughCreditsForRealtime() {
    final summary = ref.read(creditSummaryProvider).asData?.value;
    if (summary == null) return false;
    return summary.hasAtLeastUsd(kRealtimeMinCreditUsd);
  }

  Future<void> setRealtimeTranscribe(bool value) async {
    if (state.phase != RecordingPhase.idle) return;

    if (value && !_hasEnoughCreditsForRealtime()) {
      // 録音自体は常に可能なので、ここでブロックするのはRealtimeのON操作のみ。
      state = state.copyWith(
        errorMessage: 'Not enough credits for Realtime Transcribe. Recording will still work without it.',
      );
      return;
    }

    state = state.copyWith(realtimeTranscribe: value, clearErrorMessage: true);
    // Preferences に保存
    await RecordingPreferences().setRealtimeTranscribe(value);
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

      // 2. 最後のチャンクをフラッシュして登録（Realtime Transcribe が On の場合のみ）
      if (state.realtimeTranscribe) {
        final finalFlushed = _chunker?.flush();
        if (finalFlushed != null && finalFlushed.data.isNotEmpty) {
          DevLog.add('[Chunker] Final chunk is ready! Size: ${finalFlushed.data.length} bytes (Start: ${finalFlushed.startTimeSec}s)');

          final path = await _recorder.savePcmAsM4a(finalFlushed.data, lecture.id);

          await _repo.attachAudioAndEnqueueUpload(
            userId: lecture.userId,
            lectureId: lecture.id,
            localPath: path,
            sequenceIndex: _currentChunkIndex,
            startTime: finalFlushed.startTimeSec,
          );
          _currentChunkIndex++;
        }
      } else {
        DevLog.add('[Upload] Realtime Transcribe is OFF, skipping final chunk upload');
        _chunker?.flush(); // メモリ解放のためflushは呼ぶが結果は使わない
      }

      // 3. マスターオーディオのアップロードジョブを登録
      await _repo.enqueueMasterAudioUpload(
        userId: lecture.userId,
        lectureId: lecture.id,
        localPath: masterM4aPath,
      );

      await _repo.finishLectureRecording(
        lectureId: lecture.id,
        expectedChunks: _currentChunkIndex,
      );

      state = state.copyWith(phase: RecordingPhase.queued);
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error, 
        errorMessage: 'Save failed: $e'
      );
    }
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

  Future<void> uploadAudioFile(String localFilePath) async {
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

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }

  void clearTransientNotice() {
    if (state.transientNotice == null) return;
    state = state.copyWith(clearTransientNotice: true);
  }
}