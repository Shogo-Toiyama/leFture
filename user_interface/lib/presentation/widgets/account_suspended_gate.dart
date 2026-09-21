import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 停止中アカウントには[child]の代わりに[AccountSuspendedPage]を表示する。
/// 録音・クレジット購入など「閲覧以外」の入口になるルートに被せる。
/// 実際の拒否はバックエンドが行うので、ここは案内のためのUIに過ぎない。
/// サマリー未取得(ロード中・エラー)時はchildをそのまま出す —— 誤って
/// 正常なユーザーをブロックするより、バックエンドの403に任せる方が安全。
class AccountSuspendedGate extends ConsumerWidget {
  const AccountSuspendedGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suspended = ref.watch(creditSummaryProvider).asData?.value.suspended ?? false;
    return suspended ? const AccountSuspendedPage() : child;
  }
}

class AccountSuspendedPage extends StatelessWidget {
  const AccountSuspendedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.universe;

    return Scaffold(
      backgroundColor: colors.voidBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 56, color: colors.textComet),
                const SizedBox(height: 20),
                Text(
                  l10n.accountSuspendedTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textStarlight,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.accountSuspendedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textComet, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.contact),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    l10n.accountSuspendedContactButton,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plansページ上部に出す小さな注意書き。解約だけは通す必要があるため、
/// ページ全体を[AccountSuspendedGate]で塞がずにこれを使う。
class AccountSuspendedBanner extends StatelessWidget {
  const AccountSuspendedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.universe;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, size: 18, color: colors.textComet),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.accountSuspendedPlansNotice,
              style: TextStyle(color: colors.textStarlight, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
