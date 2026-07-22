// lib/application/recording/recording_language_controller.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lecture_companion_ui/core/services/recording_preferences.dart';

part 'recording_language_controller.g.dart';

/// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
/// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
/// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
/// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
/// ダウンロードを避ける)。
@Riverpod(keepAlive: true)
class RecordingLanguageController extends _$RecordingLanguageController {
  @override
  String build() => RecordingPreferences().getRecordingLanguage();

  Future<void> setLanguage(String code) async {
    await RecordingPreferences().setRecordingLanguage(code);
    state = code;
  }
}
