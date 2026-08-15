import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lefture/application/app_config/app_config_provider.dart';
import 'package:lefture/domain/entities/app_config.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

const _appStoreUrl = 'https://apps.apple.com/app/id6792620779';

/// アプリ全体をラップし、メンテナンス中・強制アップデートが必要な間だけ
/// 画面全体に不透明なオーバーレイを被せる。ローカルに保存済みのデータの
/// 閲覧自体は妨げない設計のため、[child]はオーバーレイの下でそのまま
/// 生きている(バックグラウンド同期・ローカルDB操作は継続する)。
class AppGateOverlay extends ConsumerWidget {
  const AppGateOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigControllerProvider);

    return Stack(
      children: [
        child,
        if (config.shouldShowGate) _AppGateScreen(config: config),
      ],
    );
  }
}

class _AppGateScreen extends ConsumerWidget {
  const _AppGateScreen({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isMaintenance = config.maintenance;

    final title = isMaintenance
        ? l10n.appGateMaintenanceTitle
        : l10n.appGateUpdateTitle;
    final message = isMaintenance
        ? (config.maintenanceMessage ?? l10n.appGateMaintenanceDefaultMessage)
        : (config.updateMessage ?? l10n.appGateUpdateDefaultMessage);

    return PopScope(
      canPop: false,
      child: Material(
        color: const Color(0xFF0B0B12).withValues(alpha: 0.97),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.starGold.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMaintenance
                                ? Icons.build_circle_outlined
                                : Icons.system_update_alt_rounded,
                            color: AppColors.starGold,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (!isMaintenance) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _openAppStore(context, l10n),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.starGold,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                l10n.appGateUpdateButton,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => ref
                                .read(appConfigControllerProvider.notifier)
                                .acknowledge(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.universe.textComet,
                              side: BorderSide(color: AppColors.universe.glassBorder),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isMaintenance
                                      ? l10n.appGateContinueButton
                                      : l10n.appGateUpdateLaterButton,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.appGatePartialFeaturesUnavailableDisclaimer,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.universe.textComet.withValues(alpha: 0.75),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openAppStore(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final uri = Uri.tryParse(_appStoreUrl);
    var launched = false;
    if (uri != null) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appGateOpenStoreFailedSnackbar)),
      );
    }
  }
}
