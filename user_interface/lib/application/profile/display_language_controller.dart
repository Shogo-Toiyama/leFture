import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/core/services/recording_preferences.dart';

part 'display_language_controller.g.dart';

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化される。
/// 今後 Flutter の Locale 連動等を実装する際はここを拡張する。
@Riverpod(keepAlive: true)
class DisplayLanguageController extends _$DisplayLanguageController {
  @override
  String build() => RecordingPreferences().getDisplayLanguage();

  Future<void> setLanguage(String code) async {
    await RecordingPreferences().setDisplayLanguage(code);
    state = code;
  }
}
