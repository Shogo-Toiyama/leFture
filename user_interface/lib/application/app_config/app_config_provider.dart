import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/app_config.dart';
import 'package:lefture/infrastructure/supabase/repositories/app_config_repository_supabase.dart';

part 'app_config_provider.g.dart';

/// アプリ全体のメンテナンス/強制アップデート状態を保持する。
/// [AppLifecycleSyncWatcher]から起動時・バックグラウンド復帰時に
/// [refresh]される想定。取得に失敗した場合は直前の状態を維持する
/// (フェイルオープン) — Supabase側の一時的な不調だけで
/// 全ユーザーをロックしてしまわないため。
@Riverpod(keepAlive: true)
class AppConfigController extends _$AppConfigController {
  @override
  AppConfig build() => AppConfig.unrestricted;

  AppConfigRepository get _repo =>
      AppConfigRepository(Supabase.instance.client);

  Future<void> refresh() async {
    final remote = await _fetchWithRetry();
    if (remote == null) return; // フェイルオープン: 直前の状態を維持する

    final currentBuildNumber = await _currentBuildNumber();
    final updateRequired = currentBuildNumber < remote.minBuildNumber;

    // 内容(maintenance/updateRequiredの値)が前回と変わっていなければ、
    // ユーザーが既に閉じた確認状態(acknowledged)をそのまま維持する。
    // 値が変わった(＝新しい事象が発生した)場合だけ、確認状態をリセットして
    // オーバーレイを再表示する。
    final sameAsBefore =
        state.maintenance == remote.maintenance &&
        state.updateRequired == updateRequired;

    state = AppConfig(
      maintenance: remote.maintenance,
      maintenanceMessage: remote.maintenanceMessage,
      updateRequired: updateRequired,
      updateMessage: remote.updateMessage,
      acknowledged: sameAsBefore ? state.acknowledged : false,
    );
  }

  void acknowledge() {
    state = state.copyWith(acknowledged: true);
  }

  Future<AppConfigRemoteData?> _fetchWithRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _repo.fetch();
      } catch (e) {
        DevLog.add(
          '⚠️ [AppConfig] fetch failed (attempt ${attempt + 1}/2): $e',
        );
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    }
    return null;
  }

  Future<int> _currentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }
}
