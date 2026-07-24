import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/pending_auth_action.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 現在のプロバイダー(Google/Apple)は変えず、そのプロバイダー内で
/// 別のアカウントに切り替えるためのシート。
/// 「Change Login Method」(別プロバイダーへの切り替え)とは別の操作として
/// 独立させている — 現在のプロバイダーのタイルは Change Login Method 側で
/// チェックマーク付きで無効化されるため、同じ場所で「別アカウントを選ぶ」
/// 操作をさせるとUX上分かりにくくなるため。
class ChangeAccountSheet extends HookConsumerWidget {
  const ChangeAccountSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);

    final currentProviderName =
        ref.read(authControllerProvider.notifier).getCurrentProvider();
    final currentIdentity = currentUser?.identities
        ?.where((identity) => identity.provider == currentProviderName)
        .firstOrNull;
    final currentAccountEmail = currentIdentity?.identityData?['email'] as String?;

    final isApple = currentProviderName == 'apple';
    final providerLabel = isApple ? 'Apple' : 'Google';
    final providerEnum = isApple ? OAuthProvider.apple : OAuthProvider.google;

    Future<void> handleChangeAccount() async {
      DevLog.add('[AccountFlow] tapped "Choose different $providerLabel account" '
          '(current=$currentAccountEmail)');
      isSubmitting.value = true;
      errorMessage.value = null;

      // OAuthの完了コールバック自体には「アカウント切り替え」だという印が
      // 無いため、リクエスト直前に待機中の操作を記録しておく。
      // providerLink(別プロバイダーへの切り替え)とは別の種類にして、
      // 結果画面の文言("Login method updated"ではなく"Account updated")を
      // 出し分けられるようにする。アンリンク処理自体は router.dart 側で
      // どちらの種類でも同じロジック(同一providerなら作成日時が新しい方を残す)
      // が使われる。
      await setPendingAuthAction(PendingAuthActionKind.accountSwitch, detail: providerLabel);
      DevLog.add('[AccountFlow] pending marker set (accountSwitch:$providerLabel)');

      final result = await ref
          .read(authControllerProvider.notifier)
          .switchProvider(providerEnum);

      isSubmitting.value = false;
      if (result.hasError) {
        DevLog.add('[AccountFlow] pre-browser error: ${result.error}');
        errorMessage.value = result.error.toString().replaceAll('Exception: ', '');
        return;
      }
      DevLog.add('[AccountFlow] browser launched, awaiting OAuth callback...');
      if (context.mounted) Navigator.of(context).pop();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.voidBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.myAccountChangeAccountTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.universe.textStarlight,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.changeAccountCurrentLabel(currentAccountEmail ?? providerLabel),
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF)),

            if (errorMessage.value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AppErrorBox(
                  actionName: 'switching account',
                  rawError: errorMessage.value,
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: isSubmitting.value
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.starGold),
                    )
                  : ElevatedButton(
                      onPressed: handleChangeAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        l10n.changeAccountButtonLabel(providerLabel),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
