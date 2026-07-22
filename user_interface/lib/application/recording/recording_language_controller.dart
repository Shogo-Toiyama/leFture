// lib/application/recording/recording_language_controller.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/core/services/recording_preferences.dart';

part 'recording_language_controller.g.dart';

/// 録音言語(オンデバイスASRモデル選択)の設定。変更した瞬間にその言語の
/// モデルダウンロード/バージョン整合性チェックをキックする(プロアクティブ
/// ダウンロード)。もう1つのチェックポイント(RecordingPage入場時)は
/// RecordingController.requestMicPermissionEarly() 側から呼ぶ。
@Riverpod(keepAlive: true)
class RecordingLanguageController extends _$RecordingLanguageController {
  @override
  String build() => RecordingPreferences().getRecordingLanguage();

  Future<void> setLanguage(String code) async {
    await RecordingPreferences().setRecordingLanguage(code);
    state = code;
    ref.read(asrModelManagerProvider.notifier).ensureModelReady(code);
  }
}
