import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

part 'display_language_controller.g.dart';

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化され、[userProfileRepositoryProvider] 経由で
/// user_profiles の metadata (display_language) および Supabase Auth へ同期される。
@Riverpod(keepAlive: true)
class DisplayLanguageController extends _$DisplayLanguageController {
  @override
  String build() => RecordingPreferences().getDisplayLanguage();

  Future<void> setLanguage(String code) async {
    await RecordingPreferences().setDisplayLanguage(code);
    state = code;
    try {
      await ref.read(userProfileRepositoryProvider).setDisplayLanguage(code);
    } catch (_) {}
  }
}
