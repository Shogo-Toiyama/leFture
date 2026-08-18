import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/app_language.dart';

import 'asr_engine.dart';
import 'vad_offline_engine.dart';

/// [AsrEngineFactory.createEngine]の戻り値。エンジン本体に加えて、実際に
/// 使用されたアセットグループキー(常に`kWhisperPseudoLanguageCode`)を返す。
/// LiveAsrControllerが`lastUsedAt`をスタンプする際に必要。
class AsrEngineHandle {
  const AsrEngineHandle({required this.engine, required this.groupKey});

  final AsrEngine engine;
  final String groupKey;
}

/// 言語を問わず、常に共有Whisperモデル(+共有VAD)で[AsrEngine]を組み立てる。
class AsrEngineFactory {
  AsrEngineFactory({required AsrModelManager modelManager}) : _modelManager = modelManager;

  final AsrModelManager _modelManager;

  // 教授が間を置かず喋り続ける講義でも処理が詰まらないよう、maxSpeechDurationを
  // 安全側に倒す。
  static const _whisperMaxSpeechDuration = 8.0;
  static const _minSilenceDuration = 0.6;
  static const _minSpeechDuration = 0.25;

  // 喋り始めてから1秒後と3秒後に暫定テキストを出す。確定テキストのウィンドウは
  // 変えないので品質は落ちず、増えるデコード回数は「長い無音の後の最初の
  // ウィンドウだけ最大2回」に限られる。
  static const _warmupCheckpoints = [1.0, 3.0];
  static const _warmupRearmSilenceDuration = 5.0;

  /// 必要なモデルがまだローカルに揃っていない場合はnullを返す
  /// (呼び出し側は`AsrModelManager`のready状態を先に確認する想定だが、念のため)。
  Future<AsrEngineHandle?> createEngine(String languageCode, {double initialOffsetSec = 0.0}) async {
    DevLog.add('🎙️ [AsrEngineFactory] createEngine("$languageCode") — using shared Whisper model');

    // localPathForは展開先ディレクトリを返す(VADはtar.gzに単一ファイルだけ
    // 入れて配布する想定)ので、実ファイル名まで結合する。
    final vadDir = await _modelManager.localPathFor(kVadPseudoLanguageCode);
    if (vadDir == null) {
      DevLog.add('🎙️ [AsrEngineFactory] shared VAD model not downloaded yet → no engine this session');
      return null;
    }
    final vadPath = p.join(vadDir, 'silero_vad.onnx');

    final whisperDir = await _modelManager.localPathFor(kWhisperPseudoLanguageCode);
    if (whisperDir == null) {
      DevLog.add('🎙️ [AsrEngineFactory] shared Whisper model not downloaded yet → no engine this session');
      return null;
    }
    // sherpa-onnxの規約では、language: ''(空文字)が「自動判定」を意味する。
    // 'auto'という文字列そのものは有効な言語コードとして解釈されないため、
    // ここで変換する。
    final whisperLanguage = languageCode == kAutoDetectLanguageCode ? '' : languageCode;
    DevLog.add(
      '🎙️ [AsrEngineFactory] → VadOfflineEngine/Whisper selected '
      'for "$languageCode" (whisperLanguage="$whisperLanguage", whisperDir="$whisperDir")',
    );
    return AsrEngineHandle(
      engine: VadOfflineEngine(
        recognizerConfig: sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            whisper: sherpa_onnx.OfflineWhisperModelConfig(
              encoder: p.join(whisperDir, 'encoder.onnx'),
              decoder: p.join(whisperDir, 'decoder.onnx'),
              language: whisperLanguage,
              task: 'transcribe',
            ),
            tokens: p.join(whisperDir, 'tokens.txt'),
          ),
        ),
        vadModelPath: vadPath,
        maxSpeechDuration: _whisperMaxSpeechDuration,
        minSilenceDuration: _minSilenceDuration,
        minSpeechDuration: _minSpeechDuration,
        warmupCheckpoints: _warmupCheckpoints,
        warmupRearmSilenceDuration: _warmupRearmSilenceDuration,
        initialOffsetSec: initialOffsetSec,
      ),
      groupKey: kWhisperPseudoLanguageCode,
    );
  }
}
