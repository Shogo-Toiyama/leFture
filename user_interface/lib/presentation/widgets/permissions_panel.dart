// lib/presentation/widgets/permissions_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

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
    required this.requestAll,
  });

  final Map<Permission, PermissionStatus> statuses;
  final bool loading;
  final Future<void> Function() refresh;
  final Future<void> Function(Permission) requestOne;
  final Future<void> Function(List<OnboardingPermissionSpec>) requestAll;

  bool isGranted(Permission permission) => statuses[permission]?.isGranted ?? false;
  bool isAllGranted(List<OnboardingPermissionSpec> specs) => specs.every((s) => isGranted(s.permission));
}

/// Custom flutter_hooks hook: checks + exposes live status for a fixed list
/// of permissions, plus a way to (re-)request a single one or all at once.
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

  Future<void> requestOne(Permission permission) async {
    await permission.request();
    await refresh();
  }

  Future<void> requestAll(List<OnboardingPermissionSpec> specs) async {
    for (final spec in specs) {
      final isAlreadyGranted = statuses.value[spec.permission]?.isGranted ?? false;
      if (!isAlreadyGranted) {
        await spec.permission.request();
        await refresh();
      }
    }
  }

  useEffect(() {
    refresh();
    return null;
  }, const []);

  return PermissionsStatusState(
    statuses: statuses.value,
    loading: loading.value,
    refresh: refresh,
    requestOne: requestOne,
    requestAll: requestAll,
  );
}

/// Renders the permission rows themselves — granted ones show a checkmark,
/// not-yet-granted ones show a tappable "not granted" chip that re-requests
/// just that permission.
class PermissionsRows extends StatelessWidget {
  const PermissionsRows({
    super.key,
    required this.specs,
    required this.state,
  });

  final List<OnboardingPermissionSpec> specs;
  final PermissionsStatusState state;

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
            onRetry: () => state.requestOne(specs[i].permission),
          ),
        ],
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.spec, required this.granted, required this.onRetry});

  final OnboardingPermissionSpec spec;
  final bool granted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
          const SizedBox(width: 8),
          if (granted)
            const Icon(Icons.check_circle_rounded, color: AppColors.growthGreen, size: 22)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.alertAmber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.alertAmber.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.priority_high_rounded, color: AppColors.alertAmber, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    l10n.onboardingPermissionsNotGrantedLabel,
                    style: const TextStyle(color: AppColors.alertAmber, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (granted) return cardContent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.alertAmber.withValues(alpha: 0.15),
        highlightColor: AppColors.alertAmber.withValues(alpha: 0.08),
        child: cardContent,
      ),
    );
  }
}

/// Renders an "Allow All" button that sequentially requests all ungranted permissions.
class AllowAllPermissionsButton extends HookWidget {
  const AllowAllPermissionsButton({
    super.key,
    required this.specs,
    required this.state,
    this.onCompleted,
  });

  final List<OnboardingPermissionSpec> specs;
  final PermissionsStatusState state;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    final isRequesting = useState(false);
    final allGranted = state.isAllGranted(specs);

    Future<void> handleAllowAll() async {
      if (isRequesting.value || allGranted) return;
      isRequesting.value = true;
      try {
        await state.requestAll(specs);
        if (state.isAllGranted(specs)) {
          onCompleted?.call();
        }
      } finally {
        isRequesting.value = false;
      }
    }

    if (allGranted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.growthGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.growthGreen, size: 18),
            SizedBox(width: 8),
            Text(
              'すべての権限が許可されています',
              style: TextStyle(
                color: AppColors.growthGreen,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.starGold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: (state.loading || isRequesting.value) ? null : handleAllowAll,
        icon: isRequesting.value
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
              )
            : const Icon(Icons.done_all_rounded, size: 20),
        label: Text(
          isRequesting.value ? '権限を要求中...' : 'すべての権限を許可',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
