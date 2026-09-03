import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:lefture/core/services/audio_record/audio_chunker.dart';
import 'package:lefture/core/services/background_task.dart';
import 'package:lefture/core/services/audio_record/pcm_duration_utils.dart';
import 'package:lefture/application/recording/recovery/recording_finalize.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/recording/recovery/recovery_providers.dart';
import 'package:lefture/application/sync/outbox_provider.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_moment_repository_drift.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/application/asr/live_asr_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/app_language.dart';
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

/// Flutter内部では録音言語の「自動判定」を[kAutoDetectLanguageCode]という
/// 具体的な文字列コードとして扱う(通常の言語と同じ`String`型のまま、
/// オンデバイスWhisperのモデル選択などの既存コードに`String?`を波及させ
/// ないため)。一方DB/バックエンドは元々「未設定(null)なら自動判定」という
/// 規約で統一されているので、書き込み境界(ローカルDB/Supabase)でだけ
/// このコードをnullへ変換する。
String? _dbRecordingLanguage(String code) => code == kAutoDetectLanguageCode ? null : code;

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
  // ★ 調査用: 録音中にこのproviderが想定外に作り直されていないかを追う。
  // keepAlive:trueなので通常は録音セッション中に再生成されないはずだが、
  // もし何かのinvalidateで再生成されると、録音中の_masterSinkを持つ古い
  // インスタンスがdispose()され(=そのsinkがclose)、以降ChunkerからのGetterは
  // 新しい(何も開いていない)インスタンスを指してしまう。
  DevLog.add('🆕 [AudioRecorder] provider created new instance=${identityHashCode(svc)}');
  ref.onDispose(() {
    DevLog.add('♻️ [AudioRecorder] provider disposing instance=${identityHashCode(svc)}');
    svc.dispose();
  });
  return svc;
}

// audioRecorderServiceに依存していることを明示しないと、dev_tools/側で
// ProviderScopeを使ってaudioRecorderServiceProviderをオーバーライドしても
// このControllerには一切伝播しない(常にルートコンテナの本物のマイクを使う
// インスタンスを参照し続ける)。Riverpodの仕様上、これが必須。
// recordingRecoveryServiceにも依存していることを明示する(setActiveRecordingLectureId
// 呼び出しのため)。recordingRecoveryServiceProvider自身はaudioRecorderServiceにしか
// 依存しておらずRecordingControllerを参照し返さないので、循環にはならない
// (LectureControllerの時のような相互参照とは違う一方向の依存)。
@Riverpod(keepAlive: true, dependencies: [audioRecorderService, recordingRecoveryService])
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
            endTime: flushed.startTimeSec + flushed.data.length / kMasterPcmBytesPerSecond,
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
              // 同じ録音セッションの続き。直前まで画面に出ていたオンデバイス
              // 字幕を一時停止のたびに消してしまわないようにする。
              preserveHistory: true,
            );
      }

      state = state.copyWith(phase: RecordingPhase.recording);
      return;
    }
  }

  /// RecordingPageに入った瞬間に呼ぶ早期リクエスト。「授業が始まってしまった!」
  /// という時に録音開始がもたつかないよう、実際に録音ボタンを押すより前に
  /// 済ませておく。結果は呼び出し元(RecordingPage)に返すのみで、UI状態
  /// (RecordingPhaseなど)には反映しない——実際の可否判定・エラー表示は
  /// _startRecordingSession側の既存フローに任せる。
  /// 既にpermanentlyDenied/restrictedの場合、OSはもう二度とダイアログを
  /// 出さない(特にiOS)ので再プロンプトはせず、そのままステータスを返す。
  /// 呼び出し元はその場合、設定画面への誘導ダイアログを出す判断に使う。
  Future<PermissionStatus> requestMicPermissionEarly() async {
    final status = await Permission.microphone.status;
    if (status.isGranted || status.isPermanentlyDenied || status.isRestricted) return status;
    return Permission.microphone.request();
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
        recordingLanguage: _dbRecordingLanguage(recordingLanguage),
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
      // Recording Recoveryの誤検出防止(このIDは今録音中なので孤児ではない)。
      // 理由はRecordingRecoveryService.setActiveRecordingLectureIdのコメントを参照。
      ref.read(recordingRecoveryServiceProvider).setActiveRecordingLectureId(lectureId);

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
            endTime: startTimeSec + chunkData.length / kMasterPcmBytesPerSecond,
          );

          _uploadMgr.tryProcessQueue();
        },
        onMasterDataReady: (Uint8List masterData) async {
          // ★ 調査用: このコールバックはAudioChunkerからawaitされずに呼ばれる
          // (fire-and-forget)ため、中で投げた例外は誰にも捕まらず「録音の
          // 途中から音声ファイルが伸びなくなる」のに何もログが残らない、
          // という壊れ方をしうる。原因調査のため一時的に全体をtry/catchし、
          // _recorderが録音開始時と同じインスタンスを指し続けているかも
          // 突き合わせられるようにログを残す。
          try {
            await _recorder.writeContinuousMasterData(masterData, lectureId);
            // マスター音声への追記と並行して、オンデバイスASRエンジンにも同じ
            // 生PCMを流し込む(Realtime Transcribe OFF、またはモデル未準備の
            // 場合はLiveAsrController側が何もしないので安全)。
            ref.read(liveAsrControllerProvider.notifier).acceptPcm16(masterData);
          } catch (e, st) {
            DevLog.add(
              '🔴 [StartSession] onMasterDataReady FAILED for lecture $lectureId '
              '(recorder instance=${identityHashCode(_recorder)}): $e\n$st',
            );
          }
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

      // マスター音声の継続エンコード(named pipe + fragmented MP4)を、マイクを
      // 起動するより先に開始する。ffmpegが読み手としてpipeを開いて待っている
      // 状態を作ってから書き込みを始めないと、後続の書き込みがブロックする。
      DevLog.add('[StartSession] 5.5/8 starting continuous master encode...');
      await _recorder.startContinuousMasterEncode(lectureId);

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
    ref.read(outboxSyncServiceProvider).pushAll();
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
    ref.read(outboxSyncServiceProvider).pushAll();
  }

  Future<void> deleteMoment(String id) async {
    await _momentRepo.deleteMoment(id);
    ref.read(outboxSyncServiceProvider).pushAll();
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
    // ここから先はもう「録音中」ではない(結果の成否によらず)。Recording
    // Recoveryの誤検出防止フラグを早めに下ろしておく。
    ref.read(recordingRecoveryServiceProvider).setActiveRecordingLectureId(null);

    // ★ ここから「アップロードジョブを登録し終える」までは、OSに止められては
    // いけない区間。stop()でオーディオセッションが終わると
    // UIBackgroundModes:audio の保護が切れるため、直後のFFmpegエンコード中に
    // 画面ロック・アプリ切替が起きるとiOSは数秒でアプリをサスペンドする。
    // そうなるとenqueueMasterAudioUploadに到達せず、録音は端末に残ったまま
    // サーバーへ一切送られない(テスターの講義3件がこれで丸1日取り残された)。
    // iOSへ明示的に実行猶予(概ね30秒)を要求して、この区間を守る。
    final bgTaskId = await BackgroundTask.begin('lefture.finalizeRecording');

    try {
      await _audioStreamSub?.cancel();
      // Androidのforeground serviceはここでは畳まない。あちらでアプリを
      // 生かしているのはマイクではなくサービスなので、エンコードが終わるまで
      // 残す必要がある(下のfinallyで畳む)。
      await _recorder.stop(releaseBackgroundService: false);
      await ref.read(liveAsrControllerProvider.notifier).stop();
      _timer?.cancel();

      // 1. マスター音声は録音中ずっと継続エンコードされてきている(named pipe +
      // fragmented MP4)。ここでは最後のフラグメントを確定させてファイルを
      // 閉じるだけなので、通常はほぼ一瞬で終わる。実機での所要時間を測って
      // おく(--dart-define=IS_TEST_MODE=true のビルドならDevLogオーバーレイで
      // 確認できる)。iOSの実行猶予は概ね30秒なので、ここが何秒かかっているかが
      // 再発リスクの直接の指標になる。
      final encodeStartedAt = DateTime.now();
      final masterM4aPath = await _recorder.finalizeContinuousMasterEncode(lecture.id);
      final encodeMs = DateTime.now().difference(encodeStartedAt).inMilliseconds;
      final encodedBytes = await File(masterM4aPath).length();
      final remaining = await BackgroundTask.remainingSeconds();
      DevLog.add(
        '⏱️ [Upload] Master audio finalized in ${(encodeMs / 1000).toStringAsFixed(1)}s '
        '(${(encodedBytes / (1024 * 1024)).toStringAsFixed(1)}MB m4a). '
        'Background time left: ${BackgroundTask.formatRemaining(remaining)}',
      );

      // 2. 最後のチャンクをフラッシュ（Realtime Transcribe が On の場合のみ）。
      // ここではまだDBに書き込まない — expectedChunksが確定してから
      // ジョブを登録する必要があるため(下記3を参照)。
      String? finalChunkPath;
      double? finalChunkStartTime;
      double? finalChunkEndTime;
      if (state.realtimeTranscribe) {
        final finalFlushed = _chunker?.flush();
        if (finalFlushed != null && finalFlushed.data.isNotEmpty) {
          DevLog.add('[Chunker] Final chunk is ready! Size: ${finalFlushed.data.length} bytes (Start: ${finalFlushed.startTimeSec}s)');
          finalChunkPath = await _recorder.savePcmAsM4a(finalFlushed.data, lecture.id);
          finalChunkStartTime = finalFlushed.startTimeSec;
          finalChunkEndTime = finalFlushed.startTimeSec + finalFlushed.data.length / kMasterPcmBytesPerSecond;
        }
      } else {
        DevLog.add('[Upload] Realtime Transcribe is OFF, skipping final chunk upload');
        _chunker?.flush(); // メモリ解放のためflushは呼ぶが結果は使わない
      }
      final totalChunks = finalChunkPath != null ? _currentChunkIndex + 1 : _currentChunkIndex;
      final nextChunkSequenceIndex = _currentChunkIndex;

      // 3〜6. expectedChunks確定→最終チャンク登録→マスター登録→自動分析予約、
      // の順序が重要な一連の処理はfinalizeRecordingUploadに切り出してある
      // (Recording Recoveryの確定フローとも共有するため)。
      // ★ expectedChunksを最終チャンクのジョブ登録より先に確定させる理由:
      // 以前はこれを最後(ジョブ登録の後)に書いていたため、最終チャンクの
      // ジョブ挿入(→UploadManagerがDB監視で即座に処理を開始)がexpectedChunksの
      // コミットより先に完了してしまうことがあった。その場合UploadManagerは
      // expectedChunks==nullのまま自動分析発火の判定をスキップし、以降二度と
      // 再判定されない(=自動分析が永久に発火しない)バグがあった。
      //
      // ★ 自動分析の予約が必要な理由: 最後のチャンクは「一時停止した瞬間」
      // (toggleStartStopResumeのpause分岐)にエンキューされ、多くの場合その
      // まま数秒で送信完了してしまう。ところがexpectedChunksが書かれるのは
      // ユーザーが保存を押したこの時点なので、UploadManager側の「最後の
      // チャンク完了時に発火」判定はexpectedChunks==nullのまま素通りし、
      // 以降その講義では二度とaudio_uploadジョブが完了しないため再判定される
      // 機会が無かった(保存画面で数分悩んでから保存した場合は必ずこれに該当する)。
      await finalizeRecordingUpload(
        repo: _repo,
        uploadManager: _uploadMgr,
        lecture: lecture,
        masterM4aPath: masterM4aPath,
        totalChunks: totalChunks,
        finalChunkPath: finalChunkPath,
        finalChunkStartTime: finalChunkStartTime,
        finalChunkEndTime: finalChunkEndTime,
        nextChunkSequenceIndex: nextChunkSequenceIndex,
      );
      if (finalChunkPath != null) _currentChunkIndex++;

      state = state.copyWith(phase: RecordingPhase.queued);

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Save failed: $e'
      );
    } finally {
      // 守るべき区間はここで終わり。Androidの常駐通知を畳み、iOSの実行猶予を
      // 返上する。返上を忘れるとiOSはアプリを強制終了するため、必ずfinallyで。
      await _recorder.releaseBackgroundService();
      await BackgroundTask.end(bgTaskId);
    }
  }

  Future<void> cancelAndDiscard() async {
    ref.read(recordingRecoveryServiceProvider).setActiveRecordingLectureId(null);
    await _audioStreamSub?.cancel();
    await _recorder.stop();
    await ref.read(liveAsrControllerProvider.notifier).stop();
    _timer?.cancel();
    _dbSubscription?.cancel();

    if (state.currentLectureId != null) {
      final lectureId = state.currentLectureId!;
      await _recorder.abortContinuousMasterEncode(lectureId);
      await _recorder.cleanUpMasterAudioFiles(lectureId);

      // 1. Supabase側の未完了ジョブをキャンセル
      try {
        await ref.read(jobRepositoryProvider).cancelJobsForLecture(lectureId: lectureId);
      } catch (e) {
        DevLog.add('⚠️ [CancelAndDiscard] ジョブキャンセルのエラー(無視可能): $e');
      }

      // 2. ローカルのジョブ/アセットを消してこれ以上チャンクが送られないようにする
      await _repo.deleteLectureJobsAndAssets(lectureId);

      // 3. 講義本体をローカルDBおよびSupabaseから完全物理削除(Hard Delete)
      await ref.read(lectureRepositoryProvider).hardDeleteLecture(lectureId: lectureId);
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

    // 録音の保存([upload])と同じ理由でOSに止められては困る区間。大きめの
    // 音声ファイルのコピーが挟まるうえ、途中で止まると講義行だけが作られて
    // アップロードジョブが登録されない状態になりうる。
    final bgTaskId = await BackgroundTask.begin('lefture.importAudioFile');

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
        recordingLanguage: _dbRecordingLanguage(ref.read(recordingLanguageControllerProvider)),
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
    } finally {
      await BackgroundTask.end(bgTaskId);
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

  /// 録音言語を変更する。録音中(Recording中)に呼ばれた場合は、
  /// ローカルDB/Supabaseの講義メタデータを更新し、Live ASRエンジンの
  /// 再起動を行ってシームレスに新言語へ切り替える。
  Future<void> updateRecordingLanguage(String newLanguageCode) async {
    await ref.read(recordingLanguageControllerProvider.notifier).setLanguage(newLanguageCode);

    final lectureId = state.currentLectureId;
    if (lectureId != null) {
      // 1. ローカルDBとSupabaseの講義メタデータを新言語に更新
      final dbLanguage = _dbRecordingLanguage(newLanguageCode);
      await _repo.updateLectureRecordingLanguage(lectureId, dbLanguage);
      try {
        await supabase.from('lectures').update({
          'recording_language': dbLanguage,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', lectureId);
      } catch (e) {
        DevLog.add('⚠️ [RecordingController] Failed to sync updated recording_language to Supabase: $e');
      }
    }

    // 2. 録音中かつリアルタイム文字起こしが有効なら、Live ASRエンジンを安全に引き継ぎ再起動
    if ((state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused) &&
        state.realtimeTranscribe) {
      final liveAsrNotifier = ref.read(liveAsrControllerProvider.notifier);
      final currentSec = liveAsrNotifier.currentAudioSec;
      await liveAsrNotifier.stop();
      if (state.phase == RecordingPhase.recording) {
        await liveAsrNotifier.start(
          newLanguageCode,
          initialOffsetSec: currentSec > 0 ? currentSec : state.elapsedSeconds.toDouble(),
          // 言語を変えただけで、録音セッション自体は続いている。
          // 切り替え前までのオンデバイス字幕を消してはいけない。
          preserveHistory: true,
        );
      }
    }
  }
}