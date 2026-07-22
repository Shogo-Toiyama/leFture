import 'package:shared_preferences/shared_preferences.dart';

class RecordingPreferences {
  static const String _keyRealtimeTranscribe = 'recording_realtime_transcribe';
  static const String _keyAutoStartAnalysis = 'recording_auto_start_analysis';
  static const String _keyRecordingLanguage = 'recording_language';
  static const String _keyUiLanguage = 'ui_language';

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

  /// UI言語の設定を取得（デフォルト: 'en'）。今回はまだ実際の切り替えは行わない。
  String getUiLanguage() {
    return _prefs.getString(_keyUiLanguage) ?? 'en';
  }

  /// UI言語の設定を保存
  Future<void> setUiLanguage(String value) async {
    await _prefs.setString(_keyUiLanguage, value);
  }
}
