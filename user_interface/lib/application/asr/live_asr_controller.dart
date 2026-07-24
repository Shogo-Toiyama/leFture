// lib/application/asr/live_asr_controller.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/core/services/asr_engine/asr_engine.dart';
import 'package:lefture/core/services/asr_engine/asr_engine_factory.dart';
import 'package:lefture/core/services/asr_engine/asr_live_segment.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

part 'live_asr_controller.g.dart';

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
  Future<void> start(String languageCode, {double initialOffsetSec = 0.0}) async {
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
      state = [];
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
        // 直前の行がまだ未確定(isFinal:false)なら、新しい行を増やすのではなく
        // その行を上書きする(partial→partialの更新も、partial→finalの確定も
        // どちらもここで吸収する)。
        if (current.isNotEmpty && !current.last.isFinal) {
          state = [...current.sublist(0, current.length - 1), segment];
        } else {
          state = [...current, segment];
        }
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

    final status = ref.read(asrModelManagerProvider.notifier).statusForLanguage(languageCode).status;
    if (status != AsrModelStatus.ready) return;

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
