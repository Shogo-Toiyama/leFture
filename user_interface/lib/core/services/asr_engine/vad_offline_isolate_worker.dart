import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lefture/core/utils/dev_log.dart';

import 'asr_engine_status.dart';
import 'asr_live_segment.dart';
import 'pcm_utils.dart';
import 'vad_offline_isolate_messages.dart';

/// [VadOfflineEngine]用のバックグラウンドisolateエントリポイント。
/// `sherpa_onnx`のVAD/OfflineRecognizerのdecode呼び出しはブロッキングな同期FFI
/// 呼び出しであり、メインisolate(=UIスレッド)上で呼ぶと画面操作やタイマーが
/// 丸ごと固まってしまう。この関数はメインisolateから`Isolate.spawn`で起動され、
/// 認識処理は全てこの中(専用isolate)だけで完結させる。メインisolateとは
/// PCMバイト列の送信と[AsrLiveSegment]の受信だけをやり取りする。
void vadOfflineIsolateEntry(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  // まずワーカー側の受信ポートをメインへ渡す(以降、mainSendPortはワーカーから
  // メインへの一方向送信に使い続ける — 新たなポート交換は不要)。
  mainSendPort.send(workerReceivePort.sendPort);

  _VadOfflineRecognitionLogic? logic;

  workerReceivePort.listen((dynamic message) async {
    if (message is VadOfflineIsolateConfig) {
      logic = _VadOfflineRecognitionLogic(
        recognizerConfig: message.recognizerConfig,
        vadModelPath: message.vadModelPath,
        maxSpeechDuration: message.maxSpeechDuration,
        minSilenceDuration: message.minSilenceDuration,
        minSpeechDuration: message.minSpeechDuration,
        confirmIntervalDuration: message.confirmIntervalDuration,
        warmupCheckpoints: message.warmupCheckpoints,
        warmupRearmSilenceDuration: message.warmupRearmSilenceDuration,
        initialOffsetSec: message.initialOffsetSec,
        onSegment: (segment) => mainSendPort.send(segment),
        onStatus: (status) => mainSendPort.send(status),
      );
      await logic!.start();
      mainSendPort.send(const VadOfflineIsolateReady());
    } else if (message is Uint8List) {
      logic?.acceptPcm16(message);
    } else if (message is VadOfflineIsolateSetPaused) {
      logic?.setPaused(message.paused);
    } else if (message is VadOfflineIsolateDisposeRequest) {
      await logic?.dispose();
      mainSendPort.send(const VadOfflineIsolateDisposed());
      workerReceivePort.close();
    }
  });
}

/// デコード待ちの1ジョブ。
///
/// [isFinal]がfalseの「暫定」ジョブは、より新しい暫定が来た時や処理が実時間に
/// 追いつかない時に**捨ててよい**(同じ区間はいずれ確定ジョブが上書きする)。
/// 確定ジョブは絶対に捨てない ——捨てるとその区間の文字起こしが永久に欠ける。
typedef _DecodeJob = ({Float32List samples, double timestampSec, bool isFinal});

/// Whisper(OfflineRecognizer) + Silero VADによる認識ロジック。ワーカーisolate
/// 内でのみ使う(メインisolateからは触らない)。
///
/// ## デコードのタイミング
///
/// 確定(isFinal:true)のデコードは次の2つのタイミングで1回ずつだけ行う:
///
/// 1. VADが発話の区切り(無音)を検知した時
/// 2. 区切りが来ないまま[confirmIntervalDuration]秒経った時("マシンガントーク"の保険)
///
/// これに加えて、**喋り始めの立ち上がりだけ**[warmupCheckpoints]の時点で
/// 「そこまでの音声」を暫定(isFinal:false)としてデコードする。文字起こしが
/// 出るまで数秒間まったく何も起きないと、ユーザーには本当に録音・認識されて
/// いるのか分からないため、最初だけ早めに文字を見せて安心してもらうのが目的。
///
/// 重要なのは、暫定デコードでも**ウィンドウの区切り方は一切変えていない**こと。
/// 溜めているバッファの先頭は同じままで、途中経過を読み直しているだけなので、
/// 最終的に確定するテキストは今までと同じ文脈量で作られ、品質は落ちない。
/// (チャンク自体を短くすると文脈が減って精度が落ちる——それとは別物。)
///
/// かつてプレビューを0.4秒おきに再デコードしていた頃は、8秒あたり20回近く
/// デコードが走って実機のCPUが追いつかず破綻した。ここでのチェックポイントは
/// 立ち上がりの数回だけなので、1ウィンドウあたりのデコード回数は1回→最大3回に
/// 増えるだけで済む。
///
/// VADのpop()が返す`segment.samples`はデコードに使わない(自前で溜めた
/// バッファと内容が重複するため)。pop()は「発話が区切られた」という合図
/// としてだけ使う。
class _VadOfflineRecognitionLogic {
  _VadOfflineRecognitionLogic({
    required this.recognizerConfig,
    required this.vadModelPath,
    required this.maxSpeechDuration,
    required this.minSilenceDuration,
    required this.minSpeechDuration,
    required this.confirmIntervalDuration,
    required this.warmupCheckpoints,
    required this.warmupRearmSilenceDuration,
    required this.onSegment,
    required this.onStatus,
    this.initialOffsetSec = 0.0,
  });

  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;
  final double confirmIntervalDuration;
  final List<double> warmupCheckpoints;
  final double warmupRearmSilenceDuration;
  final double initialOffsetSec;
  final void Function(AsrLiveSegment segment) onSegment;
  final void Function(VadOfflineIsolateStatus status) onStatus;

  static const _sampleRate = 16000;

  // デコードが実時間に追いつかず溜まってしまった場合、これを超えた分は
  // 間引く(取りこぼすリスクより、録音を止めてもずっと文字起こしが終わらない
  // 状態の方が実害が大きいため)。間引く順番は必ず「暫定が先、確定は最後」。
  static const _maxPendingChunks = 2;

  // これより短い音声はデコードしない。実測では、0.2秒程度の断片でも1回あたり
  // 0.35〜0.40秒のCPUを消費し、結果は必ず空だった(デコード時間は
  // 「固定コスト + 音声長 + 出力トークン数」で決まり、固定コストが支配的な
  // ため)。天井フラッシュの直後にVADの区切りが来た場合などに発生する。
  static const _minDecodeDuration = 0.3;

  // 確定フラッシュの天井までこれを切っていたら、立ち上がりの暫定デコードは
  // 見送る。デコード時間の大半は「吐き出す単語数」で決まるため、暫定は
  // 同じ単語をもう一度デコードするぶんが丸ごと上乗せになる。確定の数秒前に
  // 出しても、そのコストに見合うだけ体感は良くならない。
  static const _minWarmupHeadroom = 3.0;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VoiceActivityDetector? _vad;

  // 一時停止中に維持するリングバッファ。
  final List<Float32List> _preBuffer = [];
  int _preBufferSampleCount = 0;

  // まだデコードしていない生サンプル(発話中かどうかに関わらず常に溜める)。
  final List<Float32List> _pendingSamples = [];
  int _pendingSampleCount = 0;
  // 現在の_pendingSamplesの先頭が、録音開始から何サンプル目かを覚えておく
  // (確定テキストのtimestampSecに使う)。
  int _pendingStartSample = 0;
  int _totalSamplesFed = 0;

  // デコード処理は必ず順番通りに処理する(確定テキストの前後関係が崩れないように)。
  // 途中の要素を抜く(暫定の間引き)必要があるためQueueではなくListで持つ。
  final List<_DecodeJob> _decodeQueue = [];
  bool _isDecoding = false;

  // ---- 立ち上がりバースト ----
  // 録音開始直後は必ず武装しておく(最初の発話で暫定テキストを出す)。
  bool _burstArmed = true;
  int _nextCheckpointIndex = 0;
  // このウィンドウで暫定を実際に1回でも出したか。「天井が近いので見送った」
  // ケースと区別するために持つ ——見送っただけなら、喋り始めの文字はまだ
  // 一度も出せていないので、次のウィンドウで改めて出したい。
  bool _burstFiredInWindow = false;
  // 現在のウィンドウで最初に発話を検知した位置。チェックポイントは
  // 「ウィンドウ先頭から」ではなく「喋り始めてから」数える(録音開始後しばらく
  // 無音が続いた場合に、誰も喋っていない区間でチェックポイントを
  // 使い切ってしまわないようにするため)。nullならまだ発話が来ていない。
  int? _windowSpeechStartSample;
  // 連続した無音の長さ。これが[warmupRearmSilenceDuration]を超えると、
  // 次の発話でまたバーストする(長い間の後の「ちゃんと聞こえてるよ」)。
  int _silenceRunSamples = 0;

  // ---- 稼働状況 ----
  bool _speechDetected = false;
  int _droppedFinalCount = 0;
  VadOfflineIsolateStatus? _lastSentStatus;

  // ---- 計測 ----
  // デコードに費やした累計時間。録音の経過時間と比べた比率(デューティ比)が、
  // 端末ごとにどれだけ余裕があるかの指標になる。
  double _decodeSecTotal = 0;

  // Liveタブが非表示/アプリがバックグラウンドの間はtrueになる。この間は
  // VAD推論・バッファリング・デコードを一切行わず、サンプルカウント
  // (タイムスタンプの基準)だけを進める。
  bool _paused = false;

  Future<void> start() async {
    sherpa_onnx.initBindings();

    DevLog.add(
      '🎙️ [VadOfflineEngine/worker] start() — vadModelPath="$vadModelPath" '
      'maxSpeechDuration=${maxSpeechDuration}s minSilenceDuration=${minSilenceDuration}s '
      'minSpeechDuration=${minSpeechDuration}s confirmIntervalDuration=${confirmIntervalDuration}s',
    );

    final initialSamples = (initialOffsetSec * _sampleRate).round();
    _totalSamplesFed = initialSamples;
    _pendingStartSample = initialSamples;

    _recognizer = sherpa_onnx.OfflineRecognizer(recognizerConfig);
    _vad = sherpa_onnx.VoiceActivityDetector(
      config: sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: vadModelPath,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          maxSpeechDuration: maxSpeechDuration,
        ),
        sampleRate: _sampleRate,
      ),
      // 30秒分のリングバッファ。maxSpeechDurationより十分大きくしておく。
      bufferSizeInSeconds: 30,
    );
    DevLog.add('🎙️ [VadOfflineEngine/worker] recognizer + VAD ready');
  }

  /// Liveタブの表示状態/アプリのフォアグラウンド状態が変わった際に呼ばれる。
  /// 一時停止に入る瞬間は、直前までユーザーが実際に見ていた区間の音声を
  /// 巻き込んで捨ててしまわないよう、まず溜まっている分を通常通りflushして
  /// からフラグを立てる。再開時は特別な処理は不要(次のacceptPcm16から
  /// 通常の蓄積/flushが自然に再開する)。SileroVADの内部状態が一時停止で
  /// 不連続になることによる誤検出を避けるため、再開時にVADをリセットする。
  void setPaused(bool paused) {
    if (_paused == paused) return;
    if (paused) {
      _flushPending(force: true);
      // このtrue区間で新しく積み直す。前回の一時停止の残骸を持ち越さない。
      _preBuffer.clear();
      _preBufferSampleCount = 0;
    } else {
      _vad?.reset();
      // 一時停止中に溜めておいたリングバッファを、次のウィンドウの先頭として
      // そのまま差し込む。中断が preBufferMaxDuration 秒以内に収まっていれば
      // ここで全量を回収できるため、実質何も欠けない。それより長い中断なら
      // 直前の分だけが救われ、それより前は本当に欠けたままになる
      // (どのみちUI側が「欠けた区間」として案内を出す)。
      if (_preBuffer.isNotEmpty) {
        _pendingSamples.add(_concat(_preBuffer));
        _pendingSampleCount = _preBufferSampleCount;
        _pendingStartSample = _totalSamplesFed - _preBufferSampleCount;
        _preBuffer.clear();
        _preBufferSampleCount = 0;
      } else {
        _pendingStartSample = _totalSamplesFed;
      }
      // 一時停止明けはユーザーが再びLiveタブを見ている瞬間なので、
      // 立ち上がりバーストをやり直して早く文字を見せる。
      _burstArmed = true;
      _burstFiredInWindow = false;
      _silenceRunSamples = 0;
      _windowSpeechStartSample = null;
      _nextCheckpointIndex = 0;
    }
    _paused = paused;
    DevLog.add('⏸️ [VadOfflineEngine/worker] setPaused($paused)');
  }

  void acceptPcm16(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;

    final samples = convertPcm16ToFloat32(bytes);

    if (_paused) {
      // VAD推論・デコードは一切行わない。タイムスタンプが実時間からズレない
      // よう、サンプルカウントの歩みだけは進め続ける。
      _totalSamplesFed += samples.length;
      _speechDetected = false;
      _emitStatus();

      // 直前 preBufferMaxDuration 秒だけは捨てずに持っておく(再開時に
      // setPausedがこれを_pendingSamplesへ差し込む)。VAD/デコードを
      // 通さない単純なコピーなので、CPUコストは無視できるほど小さい。
      _preBuffer.add(samples);
      _preBufferSampleCount += samples.length;
      final maxPreBufferSamples = (kAsrLivePreBufferSeconds * _sampleRate).round();
      while (_preBufferSampleCount > maxPreBufferSamples && _preBuffer.isNotEmpty) {
        final removed = _preBuffer.removeAt(0);
        _preBufferSampleCount -= removed.length;
      }
      return;
    }

    vad.acceptWaveform(samples);
    _totalSamplesFed += samples.length;

    _pendingSamples.add(samples);
    _pendingSampleCount += samples.length;

    _updateSpeechState(vad, samples.length);

    var vadConfirmed = false;
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      // segment.samplesはデコードに使わない(自前バッファと重複するため)。
      // pop()は「発話が区切られた」という合図としてだけ使う。
      DevLog.add(
        '👂 [VadOfflineEngine/worker] VAD segment confirmed: start=${(segment.start / _sampleRate).toStringAsFixed(1)}s',
      );
      vadConfirmed = true;
    }

    final confirmIntervalSamples = (confirmIntervalDuration * _sampleRate).round();
    final reachedCeiling = _pendingSampleCount >= confirmIntervalSamples;

    if (vadConfirmed || reachedCeiling) {
      if (!vadConfirmed && reachedCeiling) {
        DevLog.add(
          '⏱️ [VadOfflineEngine/worker] no VAD pause within ${confirmIntervalDuration}s — flushing anyway',
        );
      }
      _flushPending();
      return;
    }

    _maybeDecodeWarmupPrefix();
  }

  /// VADの発話検知状態を更新し、無音が続いたら立ち上がりバーストを再武装する。
  void _updateSpeechState(sherpa_onnx.VoiceActivityDetector vad, int newSampleCount) {
    final speaking = vad.isDetected();

    if (speaking) {
      _silenceRunSamples = 0;
      // このウィンドウで最初に発話を検知した位置を覚えておく。
      _windowSpeechStartSample ??= _totalSamplesFed - newSampleCount;
    } else {
      _silenceRunSamples += newSampleCount;
      final rearmSamples = (warmupRearmSilenceDuration * _sampleRate).round();
      if (!_burstArmed && _silenceRunSamples >= rearmSamples) {
        _burstArmed = true;
        DevLog.add(
          '🔔 [VadOfflineEngine/worker] warm-up burst re-armed after '
          '${warmupRearmSilenceDuration.toStringAsFixed(0)}s of silence',
        );
      }
    }

    if (speaking != _speechDetected) {
      _speechDetected = speaking;
      _emitStatus();
    }
  }

  /// 喋り始めてから[warmupCheckpoints]秒の時点で、ウィンドウ先頭からそこまでの
  /// 音声を暫定デコードする。ウィンドウの区切り方は変えないので、後から来る
  /// 確定テキストの品質には一切影響しない。
  ///
  /// まだ発話が検知されていない間は何もしない。無音やノイズだけの断片を
  /// Whisperに渡すと平然と幻覚テキストを返すため、「安心させるための表示」が
  /// 逆に嘘を表示することになってしまう。
  void _maybeDecodeWarmupPrefix() {
    if (!_burstArmed) return;
    if (_nextCheckpointIndex >= warmupCheckpoints.length) return;

    final speechStart = _windowSpeechStartSample;
    if (speechStart == null) return;

    final elapsedSec = (_totalSamplesFed - speechStart) / _sampleRate;
    var reached = false;
    while (_nextCheckpointIndex < warmupCheckpoints.length &&
        elapsedSec >= warmupCheckpoints[_nextCheckpointIndex]) {
      _nextCheckpointIndex++;
      reached = true;
    }
    if (!reached) return;

    // 天井が目前(＝確定テキストがもうすぐ出る)なら暫定は見送る。ウィンドウの
    // 終盤で喋り始めた場合にここへ来る。実測では確定の2秒前に出る暫定に
    // 約1秒かかっており、割に合わない。
    final headroomSec = confirmIntervalDuration - _pendingSampleCount / _sampleRate;
    if (headroomSec < _minWarmupHeadroom) {
      DevLog.add(
        '⏭️ [VadOfflineEngine/worker] skipping warm-up preview — only '
        '${headroomSec.toStringAsFixed(1)}s left before the final decode',
      );
      // headroomは減る一方なので、このウィンドウではもう暫定を出さない。
      // ただし「実際には一度も出せていない」ため、バーストの武装は解かない
      // (喋り続けていれば次のウィンドウの頭で改めて出す)。
      _nextCheckpointIndex = warmupCheckpoints.length;
      return;
    }

    DevLog.add(
      '⚡ [VadOfflineEngine/worker] warm-up preview at ${elapsedSec.toStringAsFixed(1)}s '
      'after speech onset ($_nextCheckpointIndex/${warmupCheckpoints.length})',
    );
    _burstFiredInWindow = true;
    _enqueueDecode(
      samples: _concat(_pendingSamples),
      timestampSec: _pendingStartSample / _sampleRate,
      isFinal: false,
    );
  }

  /// 溜まっている音声を確定デコードへ回す。
  ///
  /// ほんの一瞬しか溜まっていない場合はデコードせず、そのまま次のウィンドウへ
  /// 持ち越す(捨てはしない)。[force]は一時停止時のように「バッファを必ず
  /// 空にしたい」場合に使い、その時だけ極小バッファを破棄する ——持ち越すと
  /// 再開後の音声と繋がって、時間的に不連続な1本になってしまうため。
  void _flushPending({bool force = false}) {
    if (_pendingSamples.isEmpty) return;

    final tooShortToDecode = _pendingSampleCount < _minDecodeDuration * _sampleRate;
    if (tooShortToDecode && !force) return;

    final timestampSec = _pendingStartSample / _sampleRate;
    final bufferedSec = _pendingSampleCount / _sampleRate;
    // 捨てるだけの場合はコピーも要らない。
    final snapshot = tooShortToDecode ? null : _concat(_pendingSamples);
    _pendingSamples.clear();
    _pendingSampleCount = 0;
    _pendingStartSample = _totalSamplesFed;

    // このウィンドウで暫定を実際に出したなら、以降は通常運転に戻す
    // (喋り続けている限り毎ウィンドウで暫定を出したりはしない)。長い無音の
    // 後にまた武装される。
    if (_burstFiredInWindow) _burstArmed = false;
    _burstFiredInWindow = false;
    _nextCheckpointIndex = 0;
    _windowSpeechStartSample = null;

    if (snapshot == null) {
      DevLog.add(
        '🧹 [VadOfflineEngine/worker] discarded ${bufferedSec.toStringAsFixed(2)}s of '
        'buffered audio (too short to decode)',
      );
      return;
    }

    _enqueueDecode(samples: snapshot, timestampSec: timestampSec, isFinal: true);
  }

  void _enqueueDecode({
    required Float32List samples,
    required double timestampSec,
    required bool isFinal,
  }) {
    if (!isFinal) {
      // より新しい暫定は、待機中の古い暫定(同じウィンドウのより短い前半部分)を
      // 完全に置き換える。古い方をデコードする意味はない。
      _decodeQueue.removeWhere((job) => !job.isFinal);
    }
    _decodeQueue.add((samples: samples, timestampSec: timestampSec, isFinal: isFinal));
    unawaited(_processDecodeQueue());
  }

  /// 実時間に追いつけていない時に待機列を切り詰める。捨てる順番は必ず
  /// 「暫定が先、確定は最後の手段」。確定を捨てるとその区間の文字起こしが
  /// 永久に欠けるため、捨てた事実は[_droppedFinalCount]としてUIまで伝える。
  void _trimDecodeQueue() {
    while (_decodeQueue.length > _maxPendingChunks) {
      final provisionalIndex = _decodeQueue.indexWhere((job) => !job.isFinal);
      if (provisionalIndex >= 0) {
        _decodeQueue.removeAt(provisionalIndex);
        DevLog.add('⚠️ [VadOfflineEngine/worker] falling behind — dropped a provisional preview');
        continue;
      }
      _decodeQueue.removeAt(0);
      _droppedFinalCount++;
      DevLog.add(
        '🚨 [VadOfflineEngine/worker] falling behind live audio — dropped a FINAL chunk '
        '(total=$_droppedFinalCount). This part of the transcript is lost.',
      );
      _emitStatus();
    }
  }

  Future<void> _processDecodeQueue() async {
    if (_isDecoding) return;
    _isDecoding = true;
    _emitStatus();
    try {
      final recognizer = _recognizer;
      if (recognizer == null) return;

      while (_decodeQueue.isNotEmpty) {
        // 1件デコードするたびに一度イベントループへ戻す。こうしないと待機中の
        // PCMメッセージが一切処理されず、間引き(_trimDecodeQueue)も新しい
        // 暫定による置き換えも効かないまま古いジョブを全部処理してしまう。
        await Future<void>.delayed(Duration.zero);
        _trimDecodeQueue();
        if (_decodeQueue.isEmpty) break;

        final job = _decodeQueue.removeAt(0);
        final chunkSec = job.samples.length / _sampleRate;

        final watch = Stopwatch()..start();
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: job.samples, sampleRate: _sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        watch.stop();

        final decodeSec = watch.elapsedMicroseconds / 1000000;
        _decodeSecTotal += decodeSec;
        final audioSec = (_totalSamplesFed - (initialOffsetSec * _sampleRate)) / _sampleRate;
        final duty = audioSec > 0 ? _decodeSecTotal / audioSec : 0.0;

        // 適応スケジューリング(端末性能に応じてデコード頻度を決める)を入れる
        // 際の入力になる計測値。chunkを変えてもdecodeがほぼ一定なら、Whisperの
        // 30秒固定窓が支配的＝「1回あたりのコストは長さに依らない」ことになる。
        DevLog.add(
          '📊 [Asr/decode] kind=${job.isFinal ? "final" : "preview"} '
          'chunk=${chunkSec.toStringAsFixed(1)}s decode=${decodeSec.toStringAsFixed(2)}s '
          'ratio=${(decodeSec / chunkSec).toStringAsFixed(2)} '
          'duty=${(duty * 100).toStringAsFixed(0)}% queue=${_decodeQueue.length} '
          'droppedFinal=$_droppedFinalCount',
        );
        DevLog.add(
          '✅ [VadOfflineEngine/worker] ${job.isFinal ? "final" : "preview"} result '
          '(t=${job.timestampSec.toStringAsFixed(1)}s): "${text.isEmpty ? "(empty)" : text}"',
        );
        // 確定は結果が空でも必ず通知する。暫定テキストだけが出ていて確定が
        // 空だった場合(ノイズに対する幻覚など)、受け取り側がその暫定行を
        // 取り消せるようにするため。暫定は空なら黙って捨てる。
        if (job.isFinal || text.isNotEmpty) {
          onSegment(
            AsrLiveSegment(text: text, timestampSec: job.timestampSec, isFinal: job.isFinal),
          );
        }
      }
    } catch (e, st) {
      DevLog.add('🚨 [VadOfflineEngine/worker] decode failed: $e\n$st');
    } finally {
      _isDecoding = false;
      _emitStatus();
    }
  }

  /// 値が変わった時だけメインisolateへ送る。
  void _emitStatus() {
    final last = _lastSentStatus;
    if (last != null &&
        last.speechDetected == _speechDetected &&
        last.decoding == _isDecoding &&
        last.droppedFinalCount == _droppedFinalCount) {
      return;
    }
    final status = VadOfflineIsolateStatus(
      speechDetected: _speechDetected,
      decoding: _isDecoding,
      droppedFinalCount: _droppedFinalCount,
    );
    _lastSentStatus = status;
    onStatus(status);
  }

  Float32List _concat(List<Float32List> chunks) {
    var total = 0;
    for (final c in chunks) {
      total += c.length;
    }
    final merged = Float32List(total);
    var offset = 0;
    for (final c in chunks) {
      merged.setAll(offset, c);
      offset += c.length;
    }
    return merged;
  }

  Future<void> dispose() async {
    DevLog.add('🎙️ [VadOfflineEngine/worker] dispose()');
    _vad?.free();
    _recognizer?.free();
  }
}
