import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/application/connectivity/connectivity_status_provider.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// アプリ全体共通で、オフライン中は画面上部（ステータスバー下）に
/// スムーズなSpotifyスタイルの「You're offline」トップバナーを表示する。
/// コンテンツ全体を下に押し下げるため、レイアウト崩れが発生しません。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 接続状態が判明するまで(初回のみ)はバナーを出さない(trueをデフォルトに)。
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          child: !isOnline
              ? Container(
                  width: double.infinity,
                  color: AppColors.cosmicBlue,
                  padding: EdgeInsets.only(
                    top: topPadding > 0 ? topPadding + 2 : 6,
                    bottom: 6,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        l10n.offlineBannerMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        Expanded(child: child),
      ],
    );
  }
}
