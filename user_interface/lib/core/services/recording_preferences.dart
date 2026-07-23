import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RecordingPreferences {
  static const String _keyRealtimeTranscribe = 'recording_realtime_transcribe';
  static const String _keyAutoStartAnalysis = 'recording_auto_start_analysis';
  static const String _keyRecordingLanguage = 'recording_language';
  static const String _keyDisplayLanguage = 'display_language';
  static const String _keyAutoPausedAsrGroupKeys = 'asr_auto_paused_group_keys';
  static const String _keyAsrLanguageGroupKeys = 'asr_language_group_keys';

  late final SharedPreferences _prefs;

  // Singleton pattern
  static final RecordingPreferences _instance = RecordingPreferences._();

  RecordingPreferences._();

  factory RecordingPreferences() {
    return _instance;
  }

  /// SharedPreferences を初期化（アプリ起動時に一度呼ぶ）
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Realtime Transcribe の設定を取得（デフォルト: false）
  bool getRealtimeTranscribe() {
    return _prefs.getBool(_keyRealtimeTranscribe) ?? false;
  }

  /// Realtime Transcribe の設定を保存
  Future<void> setRealtimeTranscribe(bool value) async {
    await _prefs.setBool(_keyRealtimeTranscribe, value);
  }

  /// Auto Start Analysis の設定を取得（デフォルト: true）
  bool getAutoStartAnalysis() {
    return _prefs.getBool(_keyAutoStartAnalysis) ?? true;
  }

  /// Auto Start Analysis の設定を保存
  Future<void> setAutoStartAnalysis(bool value) async {
    await _prefs.setBool(_keyAutoStartAnalysis, value);
  }

  /// 録音言語(オンデバイスASRモデル選択に使う)の設定を取得（デフォルト: 'en'）
  String getRecordingLanguage() {
    return _prefs.getString(_keyRecordingLanguage) ?? 'en';
  }

  /// 録音言語の設定を保存
  Future<void> setRecordingLanguage(String value) async {
    await _prefs.setString(_keyRecordingLanguage, value);
  }

  /// Display Language(コンテンツ生成の出力言語)の設定を取得（デフォルト: 'en'）。
  String getDisplayLanguage() {
    return _prefs.getString(_keyDisplayLanguage) ?? 'en';
  }

  /// Display Languageの設定を保存
  Future<void> setDisplayLanguage(String value) async {
    await _prefs.setString(_keyDisplayLanguage, value);
  }

  /// バックグラウンド移行(アプリのkillも含む)によって自動的に一時停止された
  /// ASRモデルダウンロードのgroupKey一覧。ユーザーが手動でpauseした場合は
  /// ここには含めない(次回起動時に勝手に再開させないため)。
  List<String> getAutoPausedAsrGroupKeys() {
    return _prefs.getStringList(_keyAutoPausedAsrGroupKeys) ?? const [];
  }

  Future<void> setAutoPausedAsrGroupKeys(List<String> groupKeys) async {
    await _prefs.setStringList(_keyAutoPausedAsrGroupKeys, groupKeys);
  }

  /// 録音言語コード(例: 'ja')から、そのマニフェスト解決で最後に得られた
  /// `LocalAsrModels.groupKey`(例: 'sense_voice_zh'や'_whisper')への対応表。
  /// `AsrModelManager`のmanifestキャッシュはメモリ限りで起動毎に消えるため、
  /// これが無いとアプリ起動直後(マニフェスト取得が終わるまで)は、たとえ
  /// モデル本体がディスクに揃っていても、どのgroupKeyを見ればいいかすら
  /// 分からず「未確認」としか言えない。ここに前回の解決結果を残しておく
  /// ことで、DB+ファイル存在チェックだけで即座に`ready`と判定できる。
  Map<String, String> getAsrLanguageGroupKeys() {
    final raw = _prefs.getString(_keyAsrLanguageGroupKeys);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return const {};
    }
  }

  Future<void> setAsrLanguageGroupKey(String languageCode, String groupKey) async {
    final current = Map<String, String>.from(getAsrLanguageGroupKeys());
    current[languageCode] = groupKey;
    await _prefs.setString(_keyAsrLanguageGroupKeys, jsonEncode(current));
  }
}
