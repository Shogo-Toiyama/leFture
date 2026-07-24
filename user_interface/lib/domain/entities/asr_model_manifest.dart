class AsrModelInfo {
  const AsrModelInfo({
    required this.modelId,
    required this.modelVersion,
    required this.sizeBytes,
    required this.sha256,
  });

  final String modelId;
  final int modelVersion;
  final int sizeBytes;
  final String sha256;

  factory AsrModelInfo.fromJson(Map<String, dynamic> json) {
    return AsrModelInfo(
      modelId: json['modelId'] as String,
      modelVersion: json['modelVersion'] as int,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
    );
  }
}

class AsrModelManifest {
  const AsrModelManifest({
    required this.engineCompatVersion,
    this.vad,
    this.whisper,
  });

  final int engineCompatVersion;
  // 全言語共有のVADモデル(SileroVAD)。
  final AsrModelInfo? vad;
  // 全言語共有の多言語Whisperモデル。全ての録音言語がこれを使う。
  final AsrModelInfo? whisper;

  factory AsrModelManifest.fromJson(Map<String, dynamic> json) {
    return AsrModelManifest(
      engineCompatVersion: json['engineCompatVersion'] as int,
      vad: json['vad'] != null ? AsrModelInfo.fromJson(json['vad'] as Map<String, dynamic>) : null,
      whisper:
          json['whisper'] != null ? AsrModelInfo.fromJson(json['whisper'] as Map<String, dynamic>) : null,
    );
  }
}
