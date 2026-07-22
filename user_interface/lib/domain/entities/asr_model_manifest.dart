class AsrModelInfo {
  const AsrModelInfo({
    required this.modelId,
    required this.modelVersion,
    required this.sizeBytes,
    required this.sha256,
    this.engine,
  });

  final String modelId;
  final int modelVersion;
  final int sizeBytes;
  final String sha256;
  // 'streaming_zipformer' / 'sense_voice'。languagesマップ内のエントリのみ持つ
  // (共有アセットのvad/whisperには無関係)。
  final String? engine;

  factory AsrModelInfo.fromJson(Map<String, dynamic> json) {
    return AsrModelInfo(
      modelId: json['modelId'] as String,
      modelVersion: json['modelVersion'] as int,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      engine: json['engine'] as String?,
    );
  }
}

class AsrModelManifest {
  const AsrModelManifest({
    required this.engineCompatVersion,
    required this.languages,
    this.vad,
    this.whisper,
  });

  final int engineCompatVersion;
  // Tier1(streaming_zipformer)/Tier2(sense_voice)の言語のみ。ここに無い言語は
  // 全て共有Whisper(下記)にフォールバックする。
  final Map<String, AsrModelInfo> languages;
  // 全言語共有のVADモデル(SileroVAD)。Tier2/3(sense_voice/whisper)使用時に必要。
  final AsrModelInfo? vad;
  // 全言語共有の多言語Whisperモデル。languagesに無い言語はすべてこれを使う。
  final AsrModelInfo? whisper;

  factory AsrModelManifest.fromJson(Map<String, dynamic> json) {
    final languagesJson = json['languages'] as Map<String, dynamic>? ?? {};
    return AsrModelManifest(
      engineCompatVersion: json['engineCompatVersion'] as int,
      languages: languagesJson.map(
        (code, info) => MapEntry(code, AsrModelInfo.fromJson(info as Map<String, dynamic>)),
      ),
      vad: json['vad'] != null ? AsrModelInfo.fromJson(json['vad'] as Map<String, dynamic>) : null,
      whisper:
          json['whisper'] != null ? AsrModelInfo.fromJson(json['whisper'] as Map<String, dynamic>) : null,
    );
  }
}
