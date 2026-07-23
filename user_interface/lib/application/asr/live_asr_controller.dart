// lib/application/asr/live_asr_controller.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/core/services/asr_engine/asr_engine.dart';
import 'package:lecture_companion_ui/core/services/asr_engine/asr_engine_factory.dart';
import 'package:lecture_companion_ui/core/services/asr_engine/asr_live_segment.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/asr_model_repository.dart';

part 'live_asr_controller.g.dart';

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// サーバー版(`lecture_transcripts`)とのwatermarkマージはまだ行わない
/// (今回はオンデバイス認識結果をそのまま蓄積するだけ)。
@Riverpod(keepAlive: true)
class LiveAsrController extends _$LiveAsrController {
  @override
  List<AsrLiveSegment> build() => [];

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
  // モデルが常駐している間、実際に音声が流れているかどうかに関わらず
  // 一定間隔でログを出す。「録音を止めたはずなのにモデルがまだ生きている」
  // ようなリーク(発熱の原因になりうる)を、DevLogを見るだけで気付けるように
  // するための可視化目的のタイマー。
  Timer? _heartbeat;
  static const _heartbeatInterval = Duration(seconds: 30);

  AsrEngineFactory get _factory => AsrEngineFactory(
        repository: AsrModelRepository(Supabase.instance.client),
        modelManager: ref.read(asrModelManagerProvider.notifier),
      );

  /// 必要なモデルがまだ揃っていない場合は何もしない(ログだけ残す)。
  /// その場合、そのセッションではオンデバイスのライブ字幕は出ないが、
  /// サーバー側のチャンク処理には影響しない。
  Future<void> start(String languageCode) async {
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
      final handle = await _factory.createEngine(languageCode);
      if (handle == null) {
        DevLog.add(
          '⚠️ [LiveAsrController] ASR model not ready for "$languageCode"; live captions unavailable this session.',
        );
        return;
      }

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
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _engine?.dispose();
    _engine = null;
  }
}
