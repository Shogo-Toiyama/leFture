import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:lefture/domain/entities/app_language.dart';

class RecordingPreferences {
  static const String _keyRealtimeTranscribe = 'recording_realtime_transcribe';
  static const String _keyAutoStartAnalysis = 'recording_auto_start_analysis';
  static const String _keyRecordingLanguage = 'recording_language';
  static const String _keyDisplayLanguage = 'display_language';
  static const String _keyAutoPausedAsrGroupKeys = 'asr_auto_paused_group_keys';
  static const String _keyHasSeenIntroduction = 'has_seen_introduction';

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

  /// 録音言語(オンデバイスASRモデル選択に使う)の設定を取得。
  /// ユーザー設定が未保存の初期状態では、OSの端末言語（未対応の場合は'en'）を自動初期値とする。
  String getRecordingLanguage() {
    final saved = _prefs.getString(_keyRecordingLanguage);
    if (saved != null) return saved;

    final deviceLangCode = ui.PlatformDispatcher.instance.locale.languageCode;
    return recordingLanguageFromCode(deviceLangCode).code;
  }

  /// 録音言語の設定を保存
  Future<void> setRecordingLanguage(String value) async {
    await _prefs.setString(_keyRecordingLanguage, value);
  }

  /// Display Language(コンテンツ生成の出力言語)の設定を取得。
  /// ユーザー設定が未保存の初期状態では、OSの端末言語（未対応の場合は'en'）を自動初期値とする。
  String getDisplayLanguage() {
    final saved = _prefs.getString(_keyDisplayLanguage);
    if (saved != null) return saved;

    final deviceLangCode = ui.PlatformDispatcher.instance.locale.languageCode;
    return displayLanguageFromCode(deviceLangCode).code;
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

  /// サインアップ前の Introduction(3枚のオンボーディングスライド)を、
  /// この端末で既に見たかどうか。アカウント作成前の話なのでユーザーには
  /// 紐付けず、端末ローカルの設定として一度だけ表示する。
  bool getHasSeenIntroduction() {
    return _prefs.getBool(_keyHasSeenIntroduction) ?? false;
  }

  Future<void> setHasSeenIntroduction(bool value) async {
    await _prefs.setBool(_keyHasSeenIntroduction, value);
  }
}
