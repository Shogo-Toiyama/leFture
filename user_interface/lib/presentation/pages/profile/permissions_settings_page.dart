// lib/presentation/pages/profile/permissions_settings_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/permissions_panel.dart';

/// Lets a user re-check/re-grant permissions any time after onboarding —
/// reachable from Account > Settings, right under the language tiles.
/// Reuses the exact same rows/copy as the onboarding Permissions step, just
/// without the continue-gating dialogs (there's nothing to advance past
/// here).
class PermissionsSettingsPage extends HookConsumerWidget {
  const PermissionsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final specs = buildPermissionSpecs(l10n, isAndroid: Platform.isAndroid);
    final permState = usePermissionsStatus(specs.map((s) => s.permission).toList());

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.permissionsSettingsPageTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingPermissionsSubtitle,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              PermissionsRows(specs: specs, state: permState),
            ],
          ),
        ),
      ),
    );
  }
}
