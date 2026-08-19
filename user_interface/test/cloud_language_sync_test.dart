import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await RecordingPreferences().init();
  });

  group('Cloud Language Sync & Preferences Tests', () {
    test('DisplayLanguageController syncs state from RecordingPreferences', () async {
      final prefs = RecordingPreferences();
      await prefs.setDisplayLanguage('en');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(displayLanguageControllerProvider.notifier);
      expect(container.read(displayLanguageControllerProvider), equals('en'));

      // 手動で Preferences を変更して syncFromPreferences を呼ぶ
      await prefs.setDisplayLanguage('ja');
      controller.syncFromPreferences();

      expect(container.read(displayLanguageControllerProvider), equals('ja'));
    });

    test('RecordingLanguageController syncs state from RecordingPreferences', () async {
      final prefs = RecordingPreferences();
      await prefs.setRecordingLanguage('en');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(recordingLanguageControllerProvider.notifier);
      expect(container.read(recordingLanguageControllerProvider), equals('en'));

      // 手動で Preferences を変更して syncFromPreferences を呼ぶ
      // (UserProfileRepositorySupabase.getCurrentProfile()がクラウドの
      // metadataから復元する際にこれを呼ぶので、その経路を模している)
      await prefs.setRecordingLanguage('ja');
      controller.syncFromPreferences();

      expect(container.read(recordingLanguageControllerProvider), equals('ja'));
    });

    test('RecordingPreferences stores device setup completion state per userId', () async {
      final prefs = RecordingPreferences();
      const uid1 = 'user-111';
      const uid2 = 'user-222';

      expect(prefs.getHasCompletedDeviceSetup(uid1), isFalse);
      expect(prefs.getHasCompletedDeviceSetup(uid2), isFalse);

      await prefs.setHasCompletedDeviceSetup(uid1, true);

      expect(prefs.getHasCompletedDeviceSetup(uid1), isTrue);
      expect(prefs.getHasCompletedDeviceSetup(uid2), isFalse);
    });

    // UserProfileRepositorySupabase.getCurrentProfile()は、この行に対する
    // 保留中(未push)のOutboxエントリがあれば、サーバーから取れた古い値で
    // ローカルのSharedPreferences/Riverpod状態/Driftキャッシュを上書きしない
    // ——これが「言語を変更した直後に画面遷移すると古い値へ巻き戻る」レースの
    // 修正そのもの。実際のSupabaseクライアント呼び出しやgetCurrentProfile()
    // 自体はここでは再現しない(このリポジトリにはSupabase/permission_handlerの
    // テストダブルが無く、新設するとこの修正のスコープを超えるため)。
    // その代わり、getCurrentProfile()がこの判定に使っている
    // getPendingOutboxEntityIdsの挙動そのものを固定しておく。
    test(
      'getPendingOutboxEntityIds reflects a pending user_profile change '
      '(the guard getCurrentProfile() relies on to avoid clobbering fresh local edits)',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        const uid = 'user-pending-language-change';

        expect(await db.getPendingOutboxEntityIds('user_profile'), isEmpty);

        // setDisplayLanguage/setRecordingLanguage/updateProfile等はどれも
        // entityId: uid で同じ形のOutboxエントリを積む。
        await db.enqueueOutbox(
          entityType: 'user_profile',
          entityId: uid,
          op: 'update',
        );

        final pending = await db.getPendingOutboxEntityIds('user_profile');
        expect(pending, contains(uid));
      },
    );
  });
}
