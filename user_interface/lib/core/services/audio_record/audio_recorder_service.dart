import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:record/record.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:lefture/core/services/audio_record/pcm_duration_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/presentation/pages/dev_tools/test_mode_flag.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _disposed = false;

  // 初期化済みかどうかのフラグ
  bool _isBackgroundInitialized = false;

  // マスター生PCMファイル用の永続IOSink。マイクからのデータは高頻度で届くため、
  // 呼ばれるたびに`File.writeAsBytes(mode: append, flush: true)`で開閉すると、
  // 前回の書き込み(especially fsync)が終わる前に次の呼び出しが重なり、
  // 誰にもawaitされない例外としてチャンクが静かに欠落する(録音が「早送り」に
  // なっていく不具合の原因だった)。IOSinkは内部で書き込みをキューイング・
  // 直列化するため、これを1つだけ開いて使い続けることで欠落を防ぐ。
  IOSink? _masterSink;
  String? _masterSinkLectureId;

  // ★ 調査用(録音言語変更などの設定変更直後に音声ファイルが伸びなくなる
  // 不具合の切り分け用)。原因が特定でき次第削除すること。
  int _masterWriteCallCount = 0;
  int _masterWriteByteTotal = 0;

  Future<void> _initBackgroundService() async {
    if (_isBackgroundInitialized) return;

    // Android向けの通知設定
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'leFture Recording',
      notificationText: 'Recording in progress...',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'), // アイコン
    );

    DevLog.add('[AudioRecorderService] calling FlutterBackground.initialize()...');
    // 権限と設定を初期化
    _isBackgroundInitialized = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );
    DevLog.add('[AudioRecorderService] FlutterBackground.initialize() returned: $_isBackgroundInitialized');
  }

  Future<void> start({required String outputPath}) async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // ★録音開始前にバックグラウンド実行を有効化
    if (Platform.isAndroid) {
      await _initBackgroundService();
      // 通知を出してサービス開始
      if (_isBackgroundInitialized) {
        await FlutterBackground.enableBackgroundExecution();
      }
    }

    final f = File(outputPath);
    await f.parent.create(recursive: true);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 48000,
      sampleRate: 24000,
      numChannels: 1,
    );

    await _recorder.start(config, path: outputPath);
  }

  Future<Stream<Uint8List>> startStream() async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // バックグラウンド実行を有効化 (Android)
    if (Platform.isAndroid) {
      await _initBackgroundService();
      if (_isBackgroundInitialized) {
        DevLog.add('[AudioRecorderService] calling FlutterBackground.enableBackgroundExecution()...');
        await FlutterBackground.enableBackgroundExecution();
        DevLog.add('[AudioRecorderService] enableBackgroundExecution() returned');
      }
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits, // 圧縮しない生データ（振幅計算に必須）
      sampleRate: 16000,               // 16kHz (Whisperの推奨サンプリングレート)
      numChannels: 1,                  // モノラル (データ量を半分にするため)
    );
    DevLog.add('[AudioRecorderService] calling _recorder.startStream(config)...');
    final stream = await _recorder.startStream(config);
    DevLog.add('[AudioRecorderService] _recorder.startStream(config) returned a stream');
    return stream;
  }

  Future<void> pause() async {
    if (_disposed) return;
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  /// 録音を停止する。
  ///
  /// [releaseBackgroundService]をfalseにすると、Androidのforeground service
  /// (録音中の常駐通知)を畳まずに残す。保存処理
  /// ([RecordingController.upload])はこれをfalseで呼ぶこと —— Androidで
  /// アプリを生かしているのはマイクではなくforeground serviceなので、ここで
  /// 畳むと直後のFFmpegエンコード中にプロセスを止められうる。エンコードが
  /// 終わってから[releaseBackgroundService]で明示的に畳む。
  Future<String?> stop({bool releaseBackgroundService = true}) async {
    if (_disposed) return null;

    final recording = await _recorder.isRecording();
    final paused = await _recorder.isPaused();

    if (releaseBackgroundService) {
      await this.releaseBackgroundService();
    }

    // マスター音声への書き込みも確実に終わらせる(encodeMasterRawToM4aが
    // rawファイルを読む前に、バッファ済みの内容を全てディスクへ反映させる)。
    await _closeMasterSink();

    if (!recording && !paused) return null;
    return _recorder.stop();
  }

  /// Androidのforeground service(録音中の常駐通知)を畳む。
  /// iOSでは何もしない —— あちらの実行猶予は[BackgroundTask]が受け持つ。
  /// 何度呼んでも安全。
  Future<void> releaseBackgroundService() async {
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      DevLog.add('[AudioRecorderService] disabling Android foreground service.');
      await FlutterBackground.disableBackgroundExecution();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // 念のためdispose時にもオフに
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }

    await _closeMasterSink();
    await _recorder.dispose();
  }

  /// 開いているマスター音声用IOSinkがあれば、バッファを書き出してから閉じる。
  /// すでに閉じている(null)場合は何もしない — 複数箇所(stop/dispose/
  /// encodeMasterRawToM4a/cleanUpMasterAudioFiles)から安全に呼べる。
  Future<void> _closeMasterSink() async {
    final sink = _masterSink;
    if (sink == null) return;
    // ★ 調査用: 誰がこのsinkを閉じたか(録音中に想定外のタイミングで
    // 呼ばれていないか)を追えるようにする。stack traceを添えることで
    // 「stop()からの正常な呼び出し」か「別経路からの想定外の呼び出し」かを
    // 区別できるようにする。
    DevLog.add(
      '🔒 [AudioRecorder] _closeMasterSink() closing sink for lectureId=$_masterSinkLectureId '
      '(wrote $_masterWriteByteTotal bytes over $_masterWriteCallCount calls). '
      'Caller:\n${StackTrace.current}',
    );
    _masterSink = null;
    _masterSinkLectureId = null;
    await sink.flush();
    await sink.close();
  }

  /// チャンクの生PCMデータをFFmpegでAAC(M4A)にエンコードしてローカルに保存する
  Future<String> savePcmAsM4a(Uint8List pcmData, String lectureId) async {
    final int sampleRate = 16000;
    final int channels = 1;

    final Directory dir = await getApplicationDocumentsDirectory();
    final String chunkDir = '${dir.path}/lectures/$lectureId/audio_chunks';
    await Directory(chunkDir).create(recursive: true);

    // ファイル名が被らないようにUUIDを使う
    final String uuid = const Uuid().v4();
    final String rawPath = '$chunkDir/$uuid.raw';
    final String m4aPath = '$chunkDir/$uuid.m4a';

    final File rawFile = File(rawPath);
    await rawFile.writeAsBytes(pcmData);

    final command = '-y -f s16le -ar $sampleRate -ac $channels -i "$rawPath" -c:a aac -b:a 64k "$m4aPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    // 一時rawファイルは成功・失敗にかかわらず不要なので削除
    try {
      if (await rawFile.exists()) await rawFile.delete();
    } catch (e) {
      debugPrint('⚠️ Failed to delete raw chunk file: $e');
    }

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogs();
      final errorMsg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception('FFmpeg chunk audio encoding failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg');
    }

    return m4aPath; // 保存したファイルのパスを返す
  }

  /// 指定されたレクチャーIDの一時PCMファイルパスを返す。
  /// RecordingRecoveryServiceが孤児検出のためにも参照するのでpublic。
  Future<String> getMasterRawPath(String lectureId) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/lectures/$lectureId/master_audio.raw';
  }

  /// 指定されたレクチャーIDの圧縮M4Aファイルパスを返す。
  /// RecordingRecoveryServiceが孤児検出のためにも参照するのでpublic。
  Future<String> getMasterM4aPath(String lectureId) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/lectures/$lectureId/master_audio.m4a';
  }

  // appendMasterRawDataの実行を直列化するための待ち行列。録音開始直後、
  // マイクの最初のデータが立て続けに届くと、複数の呼び出しがほぼ同時に
  // 「_masterSinkがまだnull」を見てしまい、それぞれが別々にIOSinkを開こうと
  // する競合が実機で確認された(1回の録音開始で複数のIOSinkが同じファイルに
  // 対して開かれ、後から開いた方だけが_masterSinkに残る。それ以前に別の
  // IOSinkへadd()された分はflush/closeされないまま孤立し、消える可能性が
  // あった)。IOSink自体は「開いた後の直列化」しか保証しないため、
  // 「開くかどうかの判定」自体もここで直列化する。
  Future<void> _pendingMasterWrite = Future.value();

  /// 録音中の生PCMデータをローカルファイルに追記する。
  /// マイクからのコールバック頻度で呼ばれ続けるため、呼び出しごとにファイルを
  /// 開閉するのではなく、同じlectureIdの間は1つの`IOSink`を使い続けて直列に
  /// 書き込む(呼び出しが重なってもIOSink内部のキューが順序と欠落無しを保証する)。
  Future<void> appendMasterRawData(Uint8List pcmData, String lectureId) {
    // ★ 1回の書き込み失敗が以降ずっと直列化を止めてしまわないよう、待ち行列
    // 用のfutureは常に「成功扱い」にしてから次につなぐ(実際のエラーは
    // resultFuture側でこの呼び出し元にそのまま伝える。呼び出し元
    // (AudioChunker経由・fire-and-forget)は_appendMasterRawDataSerial内で
    // 既にDevLogへ明示的にログしているので、ここで握りつぶしても消えはしない)。
    final resultFuture = _pendingMasterWrite.catchError((_) {}).then(
      (_) => _appendMasterRawDataSerial(pcmData, lectureId),
    );
    _pendingMasterWrite = resultFuture.catchError((_) {});
    return resultFuture;
  }

  Future<void> _appendMasterRawDataSerial(Uint8List pcmData, String lectureId) async {
    if (_masterSink == null || _masterSinkLectureId != lectureId) {
      // ★ 調査用: 想定外の再オープン(録音中に本来起きないはず)を検出する。
      DevLog.add(
        '🔓 [AudioRecorder] Opening/reopening master sink for lectureId=$lectureId '
        '(was: $_masterSinkLectureId, disposed=$_disposed, instance=${identityHashCode(this)})',
      );

      // 別のlectureId用のsinkが開いたままだった場合に備えて、念のため閉じる。
      await _closeMasterSink();

      final String rawPath = await getMasterRawPath(lectureId);
      final File file = File(rawPath);
      await file.parent.create(recursive: true);
      _masterSink = file.openWrite(mode: FileMode.append);
      _masterSinkLectureId = lectureId;
      _masterWriteCallCount = 0;
      _masterWriteByteTotal = 0;
    }

    try {
      _masterSink!.add(pcmData);
      _masterWriteCallCount++;
      _masterWriteByteTotal += pcmData.length;
      // ★ 調査用: 高頻度で呼ばれるため、間引いて定期的に「まだ書けている」
      // ことを可視化する(何も出なくなった瞬間 = 書き込みが止まった瞬間)。
      if (_masterWriteCallCount % 50 == 0) {
        DevLog.add(
          '✍️ [AudioRecorder] master sink alive: lectureId=$lectureId '
          '$_masterWriteCallCount writes, $_masterWriteByteTotal bytes total '
          '(instance=${identityHashCode(this)})',
        );
      }
    } catch (e, st) {
      // ★ これが本命の疑い: この関数はChunker側からawaitされずに呼ばれる
      // (fire-and-forget)ため、ここで投げた例外は誰にも捕まらない
      // 「Unhandled exception」としてどこにも見える形で残らず消えていた
      // 可能性がある。明示的にログへ出す。
      DevLog.add(
        '🔴 [AudioRecorder] appendMasterRawData FAILED for lectureId=$lectureId '
        'after $_masterWriteCallCount successful writes ($_masterWriteByteTotal bytes): $e\n$st',
      );
      rethrow;
    }
  }

  /// テスト専用: [encodeMasterRawToM4a]の直前に人為的な遅延を挟むためのフック。
  /// 実際の講義(90分)でもエンコード自体は10秒未満で終わるため、短い録音で
  /// バックグラウンド保護(iOSのbeginBackgroundTask)が効いているかを検証するには、
  /// この遅延で「iOSが本当にサスペンドを試みるまでアプリを起こしておく」必要がある。
  /// isTestModeでのみ効果を持ち、tree-shakingで通常ビルドのバイナリからは
  /// 消える(test_mode_flag.dartのコメント参照)。
  static Duration? debugEncodeDelayForTesting;

  /// ローカルに貯めたPCM生データをFFmpegでM4A(AAC)にエンコードする
  Future<String> encodeMasterRawToM4a(String lectureId) async {
    if (isTestMode && debugEncodeDelayForTesting != null) {
      DevLog.add(
        '🧪 [Test] Simulating slow encode: sleeping ${debugEncodeDelayForTesting!.inSeconds}s '
        'before running FFmpeg...',
      );
      await Future<void>.delayed(debugEncodeDelayForTesting!);
    }

    // 通常はstop()側で既に閉じられているはずだが、rawファイルを読む前に
    // バッファ済みの内容が確実にディスクへ反映されていることを保証するため、
    // 念のためここでも閉じる(既に閉じていれば何もしない)。
    await _closeMasterSink();

    final String rawPath = await getMasterRawPath(lectureId);
    final String m4aPath = await getMasterM4aPath(lectureId);

    final rawFile = File(rawPath);
    if (!await rawFile.exists()) {
      throw StateError('Master raw audio file does not exist at $rawPath');
    }

    // すでに出力ファイルが存在する場合は削除しておく
    final m4aFile = File(m4aPath);
    if (await m4aFile.exists()) {
      await m4aFile.delete();
    }

    // 16kHz, 16-bit signed little-endian, mono raw pcm を aac 64kbps にエンコードするコマンド
    final command = '-y -f s16le -ar 16000 -ac 1 -i "$rawPath" -c:a aac -b:a 64k "$m4aPath"';
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      // 成功したら元の巨大なrawファイルは削除する
      try {
        await rawFile.delete();
      } catch (e) {
        // 削除失敗は致命的ではないのでログ出力のみ
        debugPrint('⚠️ Failed to delete raw master file: $e');
      }
      return m4aPath;
    } else {
      final failStackTrace = await session.getFailStackTrace();
      final logs = await session.getLogs();
      final errorMsg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception('FFmpeg master audio encoding failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg\nStackTrace: $failStackTrace');
    }
  }

  /// 一時ファイル (raw, m4a) をクリーンアップする
  Future<void> cleanUpMasterAudioFiles(String lectureId) async {
    // 開いたままのIOSinkがファイルハンドルを握っていると削除に失敗しうるため、
    // 削除前に必ず閉じる。
    await _closeMasterSink();

    try {
      final String rawPath = await getMasterRawPath(lectureId);
      final rawFile = File(rawPath);
      if (await rawFile.exists()) {
        await rawFile.delete();
      }

      final String m4aPath = await getMasterM4aPath(lectureId);
      final m4aFile = File(m4aPath);
      if (await m4aFile.exists()) {
        await m4aFile.delete();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to clean up master audio files for lecture $lectureId: $e');
    }
  }

  // ===== Recording Recovery 用 =====
  //
  // 通常経路(stop→encodeMasterRawToM4a)と違い、復旧対象は既にプロセスが
  // 死んでいるため_masterSinkが存在しない・stop()を経由していない状態から
  // 始まる。rawファイルパスを直接渡して動く独立した経路として持つ。

  /// 復旧用: 生PCMをM4Aへ「進捗コールバック付き」で非同期エンコードする。
  /// 通常の[encodeMasterRawToM4a]([FFmpegKit.execute]で同期・進捗なし)とは
  /// 別に、[FFmpegKit.executeAsync]の`statisticsCallback`から処理済み
  /// メディア時間(ms)を受け取り、rawファイルのバイト数から算出した総尺で
  /// 割って0.0〜1.0の進捗率を[onProgress]へ継続通知する。
  ///
  /// 「0%で固まらない」ための3段ガード:
  ///   1. rawが1秒未満ならFFmpegを起動せず即座に[StateError]を投げる
  ///   2. [watchdogTimeout]の間`statisticsCallback`が一度も来なければ
  ///      セッションを強制キャンセルする(壊れたファイル・OS側のffmpeg
  ///      プロセスハング等で永久に0%のまま止まるのを防ぐ)
  ///   3. 完了時に[ReturnCode.isSuccess]を確認し、失敗ならffmpegログ付きで
  ///      例外を投げる
  ///
  /// rawファイルの削除は呼び出し側(RecordingRecoveryService)の責務。
  /// 通常経路と違い、復旧ではエンコード成功=「もう一度見せられる状態に
  /// なった」だけで、ユーザーがまだ分析/削除のどちらも選んでいないため。
  Future<String> encodeRawToM4aWithProgress({
    required String rawPath,
    required String m4aPath,
    required void Function(double progress) onProgress,
    Duration watchdogTimeout = const Duration(seconds: 20),
  }) async {
    final rawFile = File(rawPath);
    if (!await rawFile.exists()) {
      throw StateError('Raw audio file does not exist at $rawPath');
    }

    final rawLength = await rawFile.length();
    if (rawLength < kMasterPcmBytesPerSecond) {
      // 1秒未満: 意味のある音声として扱えない。FFmpegを起動する意味が無い上、
      // 起動してしまうと「0%のまま何も起きていないように見える」区間が
      // 生まれるため、ここで即座に失敗させる。
      throw StateError('Raw audio is too short to recover ($rawLength bytes).');
    }
    final totalDurationMs = pcmBytesToDuration(rawLength).inMilliseconds;

    final m4aFile = File(m4aPath);
    await m4aFile.parent.create(recursive: true);
    if (await m4aFile.exists()) {
      await m4aFile.delete();
    }

    final command = '-y -f s16le -ar 16000 -ac 1 -i "$rawPath" -c:a aac -b:a 64k "$m4aPath"';

    final completer = Completer<FFmpegSession>();
    Timer? watchdog;
    int? sessionId;

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(watchdogTimeout, () {
        DevLog.add(
          '⏱️ [Recovery] FFmpeg encode watchdog fired (no progress for ${watchdogTimeout.inSeconds}s), '
          'cancelling session $sessionId',
        );
        if (sessionId != null) {
          FFmpegKit.cancel(sessionId);
        }
      });
    }

    armWatchdog();

    final session = await FFmpegKit.executeAsync(
      command,
      (completedSession) {
        watchdog?.cancel();
        if (!completer.isCompleted) completer.complete(completedSession);
      },
      null,
      (stats) {
        armWatchdog();
        final progress = computeEncodeProgress(
          processedMs: stats.getTime(),
          totalDurationMs: totalDurationMs,
        );
        if (progress != null) onProgress(progress);
      },
    );
    sessionId = session.getSessionId();

    final completedSession = await completer.future;
    final returnCode = await completedSession.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await completedSession.getLogs();
      final errorMsg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception(
        'FFmpeg recovery encoding failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg',
      );
    }

    onProgress(1.0);
    return m4aPath;
  }

  /// 復旧用: rawが既に失われ、m4aだけが残っているケースの再生時間取得。
  /// 通常はraw(バイト数から誤差なく算出できる)を優先して使うべきで、これは
  /// あくまでフォールバック — 旧経路(encodeMasterRawToM4aは成功時にrawを
  /// 削除する)がDB書き込みの前に死んだ場合だけ、rawが失われてこちらに頼る
  /// ことになる。取得できなければnullを返す(呼び出し側は0扱いにする)。
  Future<Duration?> probeAudioDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final durationStr = session.getMediaInformation()?.getDuration();
      if (durationStr == null) return null;
      final seconds = double.tryParse(durationStr);
      if (seconds == null) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    } catch (e) {
      DevLog.add('⚠️ [Recovery] Failed to probe audio duration for $path: $e');
      return null;
    }
  }

  /// Realtimeテール回収用: master_audio.rawの[fromSeconds]以降だけを読み出す。
  /// ファイル全体をメモリに載せず、必要な範囲だけをシークして読む。
  Future<Uint8List> readMasterRawTail({
    required String lectureId,
    required double fromSeconds,
  }) async {
    final rawPath = await getMasterRawPath(lectureId);
    final rawFile = File(rawPath);
    if (!await rawFile.exists()) {
      throw StateError('Master raw audio file does not exist at $rawPath');
    }

    final offset = pcmSecondsToByteOffset(fromSeconds);
    final raf = await rawFile.open();
    try {
      final length = await raf.length();
      if (offset >= length) return Uint8List(0);
      await raf.setPosition(offset);
      return await raf.read(length - offset);
    } finally {
      await raf.close();
    }
  }
}
