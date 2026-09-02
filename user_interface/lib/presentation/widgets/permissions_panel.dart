// lib/presentation/widgets/permissions_panel.dart
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Android exposes a documented public intent that jumps straight to an
/// app's notification settings page (unlike other runtime permissions —
/// mic/camera/location — which only have a general app-details page, no
/// direct per-permission deep link). iOS has no equivalent public API
/// reachable without extra native/SPM plugin work, so it falls back to the
/// regular app-settings screen.
Future<void> openNotificationSettings() async {
  if (Platform.isAndroid) {
    final packageInfo = await PackageInfo.fromPlatform();
    final intent = AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: {'android.provider.extra.APP_PACKAGE': packageInfo.packageName},
    );
    await intent.launch();
    return;
  }
  await openAppSettings();
}

Future<void> openSpecificSettings(Permission permission) async {
  if (permission == Permission.notification) {
    await openNotificationSettings();
  } else {
    await openAppSettings();
  }
}

/// One row's worth of copy/icon for a permission, shared between the
/// onboarding Permissions step and the standalone Account > Permissions
/// settings page so both show identical rows and copy.
class OnboardingPermissionSpec {
  const OnboardingPermissionSpec({
    required this.permission,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.required = false,
  });

  final Permission permission;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  /// If true, the permission blocks forward progress (only battery
  /// optimization exemption today) instead of just being nudged.
  final bool required;
}

/// mic + notification + (Android only) battery-optimization-exemption.
List<OnboardingPermissionSpec> buildPermissionSpecs(AppLocalizations l10n, {required bool isAndroid}) {
  return [
    OnboardingPermissionSpec(
      permission: Permission.microphone,
      icon: Icons.mic_none_rounded,
      iconColor: AppColors.starGold,
      title: l10n.onboardingPermissionsMicTitle,
      subtitle: l10n.onboardingPermissionsMicSubtitle,
    ),
    OnboardingPermissionSpec(
      permission: Permission.notification,
      icon: Icons.notifications_none_rounded,
      iconColor: AppColors.cosmicBlue,
      title: l10n.onboardingPermissionsNotifTitle,
      subtitle: l10n.onboardingPermissionsNotifSubtitle,
    ),
    if (isAndroid)
      OnboardingPermissionSpec(
        permission: Permission.ignoreBatteryOptimizations,
        icon: Icons.battery_charging_full_rounded,
        iconColor: AppColors.growthGreen,
        title: l10n.onboardingPermissionsBackgroundTitle,
        subtitle: l10n.onboardingPermissionsBackgroundSubtitle,
        required: true,
      ),
  ];
}

class PermissionsStatusState {
  const PermissionsStatusState({
    required this.statuses,
    required this.loading,
    required this.refresh,
    required this.requestOne,
    required this.openSettings,
  });

  final Map<Permission, PermissionStatus> statuses;
  final bool loading;
  final Future<void> Function() refresh;
  final Future<void> Function(Permission) requestOne;
  final Future<void> Function(Permission) openSettings;

  bool isGranted(Permission permission) => statuses[permission]?.isGranted ?? false;

  /// True when the OS permission prompt hasn't been resolved yet for this
  /// permission — i.e. calling `.request()` will actually surface it (or
  /// re-surface it, on Android). False once it's granted, permanently
  /// denied, or restricted, since `.request()` is then a no-op.
  bool isUndetermined(Permission permission) => statuses[permission] == PermissionStatus.denied;

  /// True once the OS will never show its own prompt again for this
  /// permission — the row's tap target should open app Settings instead.
  bool isPermanentlyDenied(Permission permission) =>
      statuses[permission] == PermissionStatus.permanentlyDenied ||
      statuses[permission] == PermissionStatus.restricted;

  /// True when the permission status is determined (either granted or permanently denied/restricted).
  bool isDetermined(Permission permission) =>
      isGranted(permission) || isPermanentlyDenied(permission);
}

/// Custom flutter_hooks hook: checks + exposes live status for a fixed list
/// of permissions, plus a way to (re-)request a single one or open settings.
PermissionsStatusState usePermissionsStatus(List<Permission> permissions) {
  final statuses = useState<Map<Permission, PermissionStatus>>({});
  final loading = useState(true);

  Future<void> refresh() async {
    final next = <Permission, PermissionStatus>{};
    for (final permission in permissions) {
      next[permission] = await permission.status;
    }
    statuses.value = next;
    loading.value = false;
  }

  Future<void> openSettings(Permission permission) async {
    await openSpecificSettings(permission);
  }

  // permanentlyDenied/restrictedだとOS側は二度とダイアログを出さないので
  // (特にiOS)、request()を呼んでも何も起きない。その場合はアプリの設定
  // 画面を直接開く — permission_handlerのopenAppSettings()はiOS/Android
  // 共通で使える。
  Future<void> requestOrOpenSettings(Permission permission) async {
    final current = statuses.value[permission];
    if (current == PermissionStatus.permanentlyDenied || current == PermissionStatus.restricted) {
      await openSpecificSettings(permission);
    } else {
      await permission.request();
    }
  }

  Future<void> requestOne(Permission permission) async {
    await requestOrOpenSettings(permission);
    await refresh();
  }

  useOnAppLifecycleStateChange((previous, current) {
    if (current == AppLifecycleState.resumed) {
      refresh();
    }
  });

  useEffect(() {
    refresh();
    return null;
  }, const []);

  return PermissionsStatusState(
    statuses: statuses.value,
    loading: loading.value,
    refresh: refresh,
    requestOne: requestOne,
    openSettings: openSettings,
  );
}

/// Renders the permission rows.
class PermissionsRows extends StatelessWidget {
  const PermissionsRows({
    super.key,
    required this.specs,
    required this.state,
    this.isOnboarding = false,
  });

  final List<OnboardingPermissionSpec> specs;
  final PermissionsStatusState state;
  final bool isOnboarding;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppColors.starGold, strokeWidth: 2.5)),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _PermissionRow(
            spec: specs[i],
            granted: state.isGranted(specs[i].permission),
            permanentlyDenied: state.isPermanentlyDenied(specs[i].permission),
            isOnboarding: isOnboarding,
            onOpenSettings: () => state.openSettings(specs[i].permission),
            onRequest: () => state.requestOne(specs[i].permission),
          ),
        ],
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.spec,
    required this.granted,
    required this.permanentlyDenied,
    required this.isOnboarding,
    required this.onOpenSettings,
    required this.onRequest,
  });

  final OnboardingPermissionSpec spec;
  final bool granted;
  final bool permanentlyDenied;
  final bool isOnboarding;
  final VoidCallback onOpenSettings;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final isDetermined = granted || permanentlyDenied;

    // 「権限が許可・無許可のどちらかに確定してる」状態なら設定ページに飛ぶ。
    // 確定していない時：
    // - オンボーディング時はタップ無効（下のContinueボタンのみ）。
    // - 設定画面時はタップでリクエスト。
    final VoidCallback? onTap = isDetermined
        ? onOpenSettings
        : (isOnboarding ? null : onRequest);

    Widget? trailingWidget;
    if (granted) {
      trailingWidget = const Icon(Icons.check_circle_rounded, color: AppColors.growthGreen, size: 22);
    } else if (permanentlyDenied) {
      trailingWidget = Icon(Icons.settings_outlined, color: AppColors.universe.textComet, size: 20);
    } else {
      if (!isOnboarding) {
        trailingWidget = Icon(Icons.arrow_forward_ios_rounded, color: AppColors.universe.textComet, size: 14);
      }
    }

    final cardContent = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted ? AppColors.growthGreen.withValues(alpha: 0.4) : AppColors.universe.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: spec.iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(spec.icon, color: spec.iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.subtitle,
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: 8),
            trailingWidget,
          ],
        ],
      ),
    );

    if (onTap == null) return cardContent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.universe.glassWhiteLow,
        highlightColor: AppColors.universe.glassWhiteLow,
        child: cardContent,
      ),
    );
  }
}

