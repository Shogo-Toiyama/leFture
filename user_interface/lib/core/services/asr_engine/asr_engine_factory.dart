import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/asr_model_repository.dart';

import 'asr_engine.dart';
import 'streaming_zipformer_engine.dart';
import 'vad_offline_engine.dart';

/// [AsrEngineFactory.createEngine]の戻り値。エンジン本体に加えて、実際に
/// 使用されたアセットグループキー(通常はmodelId、フォールバックは
/// `kWhisperPseudoLanguageCode`)を返す。LiveAsrControllerがLRU判定用の
/// `lastUsedAt`をスタンプする際に必要。
class AsrEngineHandle {
  const AsrEngineHandle({required this.engine, required this.groupKey});

  final AsrEngine engine;
  final String groupKey;
}

/// マニフェストの`engine`(languagesマップにあればstreaming_zipformer/sense_voice、
/// 無ければ共有Whisper)に応じて、対応する[AsrEngine]実装を組み立てる。
class AsrEngineFactory {
  AsrEngineFactory({required AsrModelRepository repository, required AsrModelManager modelManager})
      : _repository = repository,
        _modelManager = modelManager;

  final AsrModelRepository _repository;
  final AsrModelManager _modelManager;

  // 教授が間を置かず喋り続ける講義でも処理が詰まらないよう、Whisperは短め・
  // SenseVoiceは軽いのでやや長めに、maxSpeechDurationを安全側に倒す。
  static const _whisperMaxSpeechDuration = 8.0;
  static const _senseVoiceMaxSpeechDuration = 16.0;
  // StreamingZipformerEngine側のrule2MinTrailingSilence(0.6s)と揃える。
  // Silero VADにはrule1相当(発話ゼロでも無音だけで確定する)の閾値が無く、
  // 実際に発話を検知した後の無音でセグメントを切る側のみ対応するため、
  // rule2側の値だけをそのまま流用している。
  static const _minSilenceDuration = 0.6;
  static const _minSpeechDuration = 0.25;

  /// 必要なモデルがまだローカルに揃っていない場合はnullを返す
  /// (呼び出し側は`AsrModelManager`のready状態を先に確認する想定だが、念のため)。
  Future<AsrEngineHandle?> createEngine(String languageCode) async {
    final manifest = await _repository.fetchManifest();
    final info = manifest.languages[languageCode];
    DevLog.add(
      '🎙️ [AsrEngineFactory] createEngine("$languageCode") — manifest entry: '
      '${info == null ? "NONE (not in languages map)" : 'engine="${info.engine}", modelId="${info.modelId}", modelVersion=${info.modelVersion}'}',
    );

    if (info != null && info.engine == 'streaming_zipformer') {
      final groupKey = resolveAssetGroupKey(manifest, languageCode);
      final modelDir = await _modelManager.localPathFor(groupKey);
      if (modelDir == null) {
        DevLog.add(
          '🎙️ [AsrEngineFactory] Tier1 streaming_zipformer matched for "$languageCode" '
          'but model not downloaded yet (groupKey="$groupKey") → no engine this session',
        );
        return null;
      }
      DevLog.add(
        '🎙️ [AsrEngineFactory] → Tier1 StreamingZipformerEngine selected '
        '(groupKey="$groupKey", modelDir="$modelDir")',
      );
      return AsrEngineHandle(
        engine: StreamingZipformerEngine(modelDir: modelDir),
        groupKey: groupKey,
      );
    }

    // localPathForは展開先ディレクトリを返す(VADはtar.gzに単一ファイルだけ
    // 入れて配布する想定)ので、実ファイル名まで結合する。
    final vadDir = await _modelManager.localPathFor(kVadPseudoLanguageCode);
    if (vadDir == null) {
      DevLog.add('🎙️ [AsrEngineFactory] shared VAD model not downloaded yet → no engine this session');
      return null;
    }
    final vadPath = p.join(vadDir, 'silero_vad.onnx');

    if (info != null && info.engine == 'sense_voice') {
      final groupKey = resolveAssetGroupKey(manifest, languageCode);
      final modelDir = await _modelManager.localPathFor(groupKey);
      if (modelDir == null) {
        DevLog.add(
          '🎙️ [AsrEngineFactory] Tier2 sense_voice matched for "$languageCode" '
          'but model not downloaded yet (groupKey="$groupKey") → no engine this session',
        );
        return null;
      }
      DevLog.add(
        '🎙️ [AsrEngineFactory] → Tier2 VadOfflineEngine/SenseVoice selected '
        '(groupKey="$groupKey", modelDir="$modelDir")',
      );
      return AsrEngineHandle(
        engine: VadOfflineEngine(
          recognizerConfig: sherpa_onnx.OfflineRecognizerConfig(
            model: sherpa_onnx.OfflineModelConfig(
              senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
                model: p.join(modelDir, 'model.onnx'),
                language: languageCode,
                useInverseTextNormalization: true,
              ),
              tokens: p.join(modelDir, 'tokens.txt'),
            ),
          ),
          vadModelPath: vadPath,
          maxSpeechDuration: _senseVoiceMaxSpeechDuration,
          minSilenceDuration: _minSilenceDuration,
          minSpeechDuration: _minSpeechDuration,
        ),
        groupKey: groupKey,
      );
    }

    // languagesマップに無い言語(スペイン語/フランス語/ドイツ語等) → 共有Whisper。
    final whisperDir = await _modelManager.localPathFor(kWhisperPseudoLanguageCode);
    if (whisperDir == null) {
      DevLog.add('🎙️ [AsrEngineFactory] shared Whisper model not downloaded yet → no engine this session');
      return null;
    }
    DevLog.add(
      '🎙️ [AsrEngineFactory] → Tier3 VadOfflineEngine/Whisper FALLBACK selected '
      'for "$languageCode" (whisperDir="$whisperDir") — this is NOT true streaming',
    );
    return AsrEngineHandle(
      engine: VadOfflineEngine(
        recognizerConfig: sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            whisper: sherpa_onnx.OfflineWhisperModelConfig(
              encoder: p.join(whisperDir, 'encoder.onnx'),
              decoder: p.join(whisperDir, 'decoder.onnx'),
              language: languageCode,
              task: 'transcribe',
            ),
            tokens: p.join(whisperDir, 'tokens.txt'),
          ),
        ),
        vadModelPath: vadPath,
        maxSpeechDuration: _whisperMaxSpeechDuration,
        minSilenceDuration: _minSilenceDuration,
        minSpeechDuration: _minSpeechDuration,
      ),
      groupKey: kWhisperPseudoLanguageCode,
    );
  }
}
