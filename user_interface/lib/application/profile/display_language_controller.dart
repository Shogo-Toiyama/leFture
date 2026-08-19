import 'dart:async';
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
    if (state == code) return;
    // UI表示状態を真っ先に更新して0msで反映
    state = code;

    // ディスク保存やDB/Outbox書き込みは非同期バックグラウンドで実行
    unawaited(RecordingPreferences().setDisplayLanguage(code));
    unawaited(Future(() async {
      try {
        await ref.read(userProfileRepositoryProvider).setDisplayLanguage(code);
      } catch (_) {}
    }));
  }

  /// SharedPreferences に保存されている最新の表示言語を取り込んで状態を更新する。
  /// （ログイン時のクラウドからの同期復元時などに利用）
  void syncFromPreferences() {
    final lang = RecordingPreferences().getDisplayLanguage();
    if (state != lang) {
      state = lang;
    }
  }
}

