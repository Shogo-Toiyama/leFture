// lib/application/asr/live_asr_controller.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/core/services/asr_engine/asr_engine.dart';
import 'package:lefture/core/services/asr_engine/asr_engine_factory.dart';
import 'package:lefture/core/services/asr_engine/asr_engine_status.dart';
import 'package:lefture/core/services/asr_engine/asr_live_segment.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

part 'live_asr_controller.g.dart';

/// 端末での文字起こしを省略した区間(録音全体の経過秒数で表す)。
///
/// Liveタブを離れている間・アプリがバックグラウンドの間は、電力と発熱を
/// 抑えるためデコードを完全に止めている。その区間だけオンデバイスの字幕が
/// 存在しないので、UI上は文字が丸ごと抜けたように見えてしまう。実際には
/// 録音そのものは続いていて、サーバー側の文字起こしが追いつけば必ず埋まる
/// ため、「壊れて空白になっている」のではないことを伝えるためにこの範囲を
/// 覚えておく。
class AsrTranscriptGap {
  const AsrTranscriptGap({required this.startSec, this.endSec});

  /// 省略が始まった位置(録音開始からの秒数)。
  final double startSec;

  /// 省略が終わった位置。nullなら現在も省略中(まだLiveタブに戻っていない)。
  final double? endSec;

  AsrTranscriptGap closedAt(double sec) => AsrTranscriptGap(startSec: startSec, endSec: sec);
}

/// Liveタブが「今ちゃんと聞こえていて処理が動いているか」を出すための状態。
///
/// 文字起こしは仕組み上どうしても数秒待たされる。その間ずっと画面が
/// 無反応だと、ユーザーには本当に録音・認識されているのか分からない
/// (「10秒待たされる」以上に「動いているのか分からない」ことの方が
/// 不安の原因になる)。テキスト以外の手がかりを常時出すために使う。
class LiveAsrStatusState {
  const LiveAsrStatusState({
    this.engineRunning = false,
    this.speechDetected = false,
    this.decoding = false,
    this.droppedFinalCount = 0,
    this.gaps = const [],
  });

  /// オンデバイスASRエンジンが起動済みか(モデル未DL/起動待ちならfalse)。
  final bool engineRunning;

  /// VADが今この瞬間、発話を検知しているか。
  final bool speechDetected;

  /// デコード(認識)を実行中か。
  final bool decoding;

  /// 端末の処理が追いつかず捨てた確定チャンクの累計(＝欠けた区間の数)。
  final int droppedFinalCount;

  /// 節電のため端末での文字起こしを省略した区間。
  final List<AsrTranscriptGap> gaps;

  LiveAsrStatusState copyWith({
    bool? engineRunning,
    bool? speechDetected,
    bool? decoding,
    int? droppedFinalCount,
    List<AsrTranscriptGap>? gaps,
  }) {
    return LiveAsrStatusState(
      engineRunning: engineRunning ?? this.engineRunning,
      speechDetected: speechDetected ?? this.speechDetected,
      decoding: decoding ?? this.decoding,
      droppedFinalCount: droppedFinalCount ?? this.droppedFinalCount,
      gaps: gaps ?? this.gaps,
    );
  }

  static const idle = LiveAsrStatusState();
}

/// [LiveAsrController]が持つエンジンの稼働状況。認識テキスト本体
/// ([LiveAsrController]のstate)とは更新頻度も用途も違うため、別のproviderに
/// 分けている(テキストが増えないタイミングでも毎秒動く表示に使うため)。
@Riverpod(keepAlive: true)
class LiveAsrStatus extends _$LiveAsrStatus {
  @override
  LiveAsrStatusState build() => LiveAsrStatusState.idle;

  void update(LiveAsrStatusState value) => state = value;

  /// ワーカー由来の稼働状況だけを差し替える(ギャップ情報は[LiveAsrController]が
  /// 別のタイミングで積むので、こちらで消してしまわないようにする)。
  void updateEngineStatus({
    required bool engineRunning,
    required bool speechDetected,
    required bool decoding,
    required int droppedFinalCount,
  }) {
    state = state.copyWith(
      engineRunning: engineRunning,
      speechDetected: speechDetected,
      decoding: decoding,
      droppedFinalCount: droppedFinalCount,
    );
  }

  void setGaps(List<AsrTranscriptGap> gaps) => state = state.copyWith(gaps: gaps);

  void reset() => state = LiveAsrStatusState.idle;
}

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// このControllerはオンデバイス認識結果をそのまま蓄積するだけで、
/// サーバー版(`lecture_transcripts`)とのwatermark除外は行わない
/// (表示側の`_LiveTranscriptPanel`がサーバー側の最新start_timeより前の
/// セグメントを描画時にフィルタしている)。
@Riverpod(keepAlive: true)
class LiveAsrController extends _$LiveAsrController {
  @override
  List<AsrLiveSegment> build() {
    final observer = _LiveAsrLifecycleObserver(
      onForegroundChanged: (foregrounded) {
        _appForegrounded = foregrounded;
        _applyPausedState();
      },
    );
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

    // モデルのダウンロード中に録音が始まった場合、start()はその場では
    // 一度失敗して諦めるだけだった(録音中ずっと字幕が出ないまま終わる
    // バグがあった)。ダウンロードが完了してモデルがreadyになったら、
    // 保留しておいた言語で自動的にstart()をやり直す。
    ref.listen(asrModelManagerProvider, (previous, next) => _maybeRetryPendingStart());

    return [];
  }

  AsrEngine? _engine;
  StreamSubscription<AsrLiveSegment>? _subscription;
  StreamSubscription<AsrEngineStatus>? _statusSubscription;
  bool _starting = false;
  // start()実行中(モデルロード/isolate起動待ち)にstop()が呼ばれた場合、
  // start()完了直後に即dispose()できるようにするためのフラグ。これが無いと
  // 「start()完了 → _engineにセット」が「stop()実行(この時点では_engineが
  // まだnullなので何もしない)」の後に起きてしまい、エンジンがどこからも
  // dispose されないまま延々isolateが起動状態で残ってしまう
  // (録音開始直後にエラーが起きて即エラー状態になるケースで実際に発生していた)。
  bool _stopRequested = false;
  // Liveタブが表示中かどうか(RecordingPageから`setLiveTabFocused`で通知される)。
  // 初期値はfalse — RecordingPageの初期タブはVoiceであり、明示的な同期を
  // 待たずとも「最初は一時停止」がデフォルトになるようにするため。
  bool _tabFocused = false;
  // アプリがフォアグラウンドかどうか(内蔵のWidgetsBindingObserverが更新)。
  bool _appForegrounded = true;

  // ---- 節電のため文字起こしを省略した区間の記録 ----
  // 現在デコードを止めているか(_applyPausedStateの立ち上がり/立ち下がりを
  // 検出するために持つ。同じ値で何度呼ばれても区間を二重に積まない)。
  bool _decodingPaused = false;
  // 今のエンジンセッションが録音全体のどこから始まったか。一時停止→再開で
  // エンジンを起動し直すたびに、呼び出し側から渡されるinitialOffsetSecが入る。
  double _sessionOffsetSec = 0;
  // エンジン起動からの経過時間。録音中は音声の進みと実時間が一致するので、
  // これに_sessionOffsetSecを足せば「録音全体での現在位置」になる
  // (ギャップ表示の境界に使うだけなので秒未満の誤差は問題にならない)。
  final Stopwatch _sessionClock = Stopwatch();
  final List<AsrTranscriptGap> _gaps = [];

  double get _currentAudioSec => _sessionOffsetSec + _sessionClock.elapsedMilliseconds / 1000.0;
  double get currentAudioSec => _currentAudioSec;
  // モデルが常駐している間、実際に音声が流れているかどうかに関わらず
  // 一定間隔でログを出す。「録音を止めたはずなのにモデルがまだ生きている」
  // ようなリーク(発熱の原因になりうる)を、DevLogを見るだけで気付けるように
  // するための可視化目的のタイマー。
  Timer? _heartbeat;
  static const _heartbeatInterval = Duration(seconds: 30);
  // start()時点でモデルがまだreadyでなかった場合の、再試行待ちの言語コード。
  // モデルがreadyになった時点で`_maybeRetryPendingStart`がこれを使って
  // start()をやり直す。
  String? _pendingRetryLanguage;
  double _pendingRetryOffsetSec = 0.0;

  AsrEngineFactory get _factory =>
      AsrEngineFactory(modelManager: ref.read(asrModelManagerProvider.notifier));

  /// 必要なモデルがまだ揃っていない場合は何もしない(ログだけ残す)。
  /// その場合、そのセッションではオンデバイスのライブ字幕は出ないが、
  /// サーバー側のチャンク処理には影響しない。
  ///
  /// [initialOffsetSec]は、録音の一時停止→再開でエンジンを起動し直す場合に、
  /// 呼び出し側(RecordingController)が把握している「録音全体でのこれまでの
  /// 経過秒数」を渡す。これが無いと、再開のたびに新しいisolateが起動して
  /// 内部のタイムスタンプが0から数え直しになり、サーバー側watermarkによる
  /// 表示フィルタ(`_LiveTranscriptPanel`)で再開後の字幕が全て消えてしまう。
  /// [preserveHistory]がtrueなら、それまでに表示していたオンデバイス字幕
  /// ([state]の中身)をクリアしない。一時停止→再開や録音言語の途中変更のように、
  /// 「同じ録音セッションの続き」としてエンジンを起動し直す場合に使う
  /// ——ここをfalse(既定)のまま呼ぶと、直前まで画面に出ていたオンデバイス
  /// 版の文字起こしが録音の途中で丸ごと消えてしまう(サーバー側の確定稿が
  /// その区間に追いつくまで、数分間ぶんの空白として見える)。新しい録音を
  /// 開始する場合(前の講義の残骸を持ち越してはいけない)だけfalseのままにする。
  Future<void> start(
    String languageCode, {
    double initialOffsetSec = 0.0,
    bool preserveHistory = false,
  }) async {
    DevLog.add('🎙️ [LiveAsrController] start("$languageCode") requested');
    if (_engine != null || _starting) {
      DevLog.add(
        '🎙️ [LiveAsrController] start() ignored (engine already ${_engine != null ? "running" : ""}${_starting ? "starting" : ""})',
      );
      return;
    }
    _starting = true;
    _stopRequested = false;
    try {
      final handle = await _factory.createEngine(languageCode, initialOffsetSec: initialOffsetSec);
      if (handle == null) {
        DevLog.add(
          '⚠️ [LiveAsrController] ASR model not ready for "$languageCode"; will retry once it '
          'finishes downloading.',
        );
        _pendingRetryLanguage = languageCode;
        _pendingRetryOffsetSec = initialOffsetSec;
        return;
      }
      _pendingRetryLanguage = null;

      final engine = handle.engine;
      await engine.start();

      if (_stopRequested) {
        DevLog.add(
          '🎙️ [LiveAsrController] stop() was requested while starting — disposing the freshly '
          'started engine instead of activating it',
        );
        await engine.dispose();
        return;
      }

      _engine = engine;
      if (!preserveHistory) state = [];
      // 一時停止→再開でエンジンを起動し直した場合も、ギャップの位置を録音
      // 全体の時間軸で表せるように、このセッションの開始位置から数え直す。
      _sessionOffsetSec = initialOffsetSec;
      _sessionClock
        ..reset()
        ..start();
      // エンジンの稼働状況をUIへ橋渡しする。「聞こえているか」の表示は、
      // 文字が出ない数秒間の唯一の手がかりになるので、エンジンが立ち上がった
      // 時点で必ず購読を張る。
      _statusSubscription = engine.status.listen((s) {
        ref
            .read(liveAsrStatusProvider.notifier)
            .updateEngineStatus(
              engineRunning: true,
              speechDetected: s.speechDetected,
              decoding: s.decoding,
              droppedFinalCount: s.droppedFinalCount,
            );
      });
      ref
          .read(liveAsrStatusProvider.notifier)
          .updateEngineStatus(
            engineRunning: true,
            speechDetected: false,
            decoding: false,
            droppedFinalCount: 0,
          );
      DevLog.add(
        '🎙️ [LiveAsrController] engine started (groupKey="${handle.groupKey}", type=${engine.runtimeType})',
      );
      // start()中に溜まっていたLiveタブ/フォアグラウンド状態を今すぐ反映する
      // (エンジンが無い間は`setLiveTabFocused`が呼ばれても何もできないため)。
      _applyPausedState();
      _startHeartbeat(handle.groupKey, engine.runtimeType.toString());
      _subscription = engine.segments.listen((raw) {
        // 「とりあえずのリアルタイム文字起こし」であることが一目で分かるよう、
        // 句読点は付けずすべて小文字で表示する(後で来るサーバー版Whisper Large
        // の確定稿は普通の大文字小文字混在+句読点になる想定なので、強調の
        // 向きが逆転しないようにするため)。
        final segment = AsrLiveSegment(
          text: raw.text.toLowerCase(),
          timestampSec: raw.timestampSec,
          isFinal: raw.isFinal,
        );
        DevLog.add(
          '📝 [LiveAsrController] ${segment.isFinal ? "FINAL" : "partial"} '
          '@ ${segment.timestampSec.toStringAsFixed(1)}s: "${segment.text}"',
        );

        final current = state;
        // 末尾の行が「同じ区間の未確定行」なら、新しい行を増やすのではなく
        // その行を置き換える(暫定→暫定の更新も、暫定→確定の確定もここで
        // 吸収する)。タイムスタンプまで一致を見るのは、別の区間の確定テキストが
        // 前の区間の暫定行を食い潰してしまわないようにするため。
        final replaceIndex =
            current.isNotEmpty &&
                !current.last.isFinal &&
                current.last.timestampSec == segment.timestampSec
            ? current.length - 1
            : null;

        if (segment.text.isEmpty) {
          // 空の確定 = その区間には結局何も無かった(ノイズだけだった)。
          // 暫定を出していたなら、それは幻覚だったということなので取り消す。
          if (segment.isFinal && replaceIndex != null) {
            state = current.sublist(0, replaceIndex);
          }
          return;
        }

        state = replaceIndex != null
            ? [...current.sublist(0, replaceIndex), segment]
            : [...current, segment];
      });
      unawaited(
        ref.read(appDatabaseProvider).touchAsrModelUsed(handle.groupKey).catchError((e, st) {
          DevLog.add('🚨 [LiveAsrController] touchAsrModelUsed failed for "${handle.groupKey}": $e\n$st');
        }),
      );
    } catch (e, st) {
      DevLog.add('🚨 [LiveAsrController] Failed to start ASR engine: $e\n$st');
      _heartbeat?.cancel();
      _heartbeat = null;
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      _sessionClock.stop();
      _decodingPaused = false;
      _gaps.clear();
      ref.read(liveAsrStatusProvider.notifier).reset();
      await _engine?.dispose();
      _engine = null;
    } finally {
      _starting = false;
    }
  }

  /// `asrModelManagerProvider`の状態が変わるたびに呼ばれる。ダウンロード中
  /// だったせいで一度startに失敗した言語(`_pendingRetryLanguage`)が
  /// readyになっていれば、start()をやり直す。
  void _maybeRetryPendingStart() {
    final languageCode = _pendingRetryLanguage;
    if (languageCode == null || _engine != null || _starting) return;

    final modelState = ref.read(asrModelManagerProvider.notifier).statusForLanguage(languageCode);
    if (!modelState.installed) return;

    DevLog.add(
      '🎙️ [LiveAsrController] model for "$languageCode" finished downloading — retrying start()',
    );
    unawaited(start(languageCode, initialOffsetSec: _pendingRetryOffsetSec));
  }

  /// Liveタブが表示中かどうかをRecordingPageから通知してもらう。タブ切り替え・
  /// ページ離脱のどちらからも呼ばれる想定(離脱時は`focused: false`)。
  void setLiveTabFocused(bool focused) {
    if (_tabFocused == focused) return;
    _tabFocused = focused;
    _applyPausedState();
  }

  /// 「Liveタブが非表示」または「アプリがバックグラウンド」のどちらかに
  /// 該当すれば、実際の認識処理(VAD推論・デコード)を一時停止する。
  /// エンジンがまだ無い(start中/未start)場合は、start()完了直後に
  /// 呼ばれる`_applyPausedState()`が改めて反映するので何もしなくてよい。
  void _applyPausedState() {
    final paused = !_tabFocused || !_appForegrounded;
    DevLog.add(
      '⏸️ [LiveAsrController] setDecodingPaused($paused) '
      '(tabFocused=$_tabFocused, appForegrounded=$_appForegrounded)',
    );
    _engine?.setDecodingPaused(paused);
    _recordGapBoundary(paused);
  }

  /// デコードの停止/再開の切り替わりで、省略した区間を記録する。
  /// エンジンが動いている間だけ意味を持つ(録音していない時の停止は
  /// そもそも文字起こしすべき音声が無いので区間にしない)。
  void _recordGapBoundary(bool paused) {
    if (_engine == null) return;
    if (paused == _decodingPaused) return;
    _decodingPaused = paused;

    if (paused) {
      _gaps.add(AsrTranscriptGap(startSec: _currentAudioSec));
    } else {
      if (_gaps.isEmpty || _gaps.last.endSec != null) return;
      _gaps[_gaps.length - 1] = _gaps.last.closedAt(_currentAudioSec);
    }
    final updatedGaps = List<AsrTranscriptGap>.unmodifiable(_gaps);
    Future.microtask(() {
      ref.read(liveAsrStatusProvider.notifier).setGaps(updatedGaps);
    });
  }

  void acceptPcm16(Uint8List bytes) {
    _engine?.acceptPcm16(bytes);
  }

  void _startHeartbeat(String groupKey, String engineType) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      DevLog.add(
        '💓 [LiveAsrController] model still resident (groupKey="$groupKey", type=$engineType) — '
        'if recording is stopped and you see this repeating, the engine failed to shut down',
      );
    });
  }

  Future<void> stop() async {
    DevLog.add('🎙️ [LiveAsrController] stop() requested (engine was ${_engine == null ? "not " : ""}running)');
    if (_starting) {
      _stopRequested = true;
    }
    _pendingRetryLanguage = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    // 録音が終われば字幕そのものが不要になるので、省略区間の記録も畳む。
    _sessionClock.stop();
    _decodingPaused = false;
    _gaps.clear();
    ref.read(liveAsrStatusProvider.notifier).reset();
    await _engine?.dispose();
    _engine = null;
  }
}

/// アプリのフォアグラウンド/バックグラウンド遷移を[LiveAsrController]へ
/// 橋渡しするだけの小さなobserver。`AsrModelManager`の`_AsrLifecycleObserver`
/// (lib/application/asr/asr_model_manager.dart)と同じ発想。inactiveは通知
/// バナー等の一時的な中断でも発火するため無視する。
class _LiveAsrLifecycleObserver extends WidgetsBindingObserver {
  _LiveAsrLifecycleObserver({required this.onForegroundChanged});

  final void Function(bool foregrounded) onForegroundChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        onForegroundChanged(false);
      case AppLifecycleState.resumed:
        onForegroundChanged(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
