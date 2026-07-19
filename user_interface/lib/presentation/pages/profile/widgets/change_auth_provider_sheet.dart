import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/pending_auth_action.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangeAuthProviderSheet extends HookConsumerWidget {
  const ChangeAuthProviderSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final currentProvider = ref.read(authControllerProvider.notifier).getCurrentProvider();
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);

    final availableProviders = [
      ('Email', OAuthProvider.google, Icons.email_outlined),
      ('Google', OAuthProvider.google, Icons.g_mobiledata),
      ('Apple', OAuthProvider.apple, Icons.apple),
    ];

    Future<void> handleSwitch(OAuthProvider provider, String name) async {
      isSubmitting.value = true;
      errorMessage.value = null;

      // OAuthの完了コールバック自体には「ログイン方法の変更」だという印が
      // 無いため、リクエスト直前に待機中の操作を記録しておく。
      await setPendingAuthAction(PendingAuthActionKind.providerLink, detail: name);

      // linkIdentity は外部ブラウザでの認証を要求するため、ここで検知できる
      // 失敗は「ブラウザを開く前」の事前チェック(未ログイン等)のみ。
      // 実際の成否はOAuthコールバック側(router.dart)の結果画面で分かる。
      final result =
          await ref.read(authControllerProvider.notifier).switchProvider(provider);

      isSubmitting.value = false;
      if (result.hasError) {
        errorMessage.value = result.error.toString().replaceAll('Exception: ', '');
        return;
      }
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
            // ── Header ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change Login Method',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.universe.textStarlight,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current: ${currentProvider?.toUpperCase() ?? "Unknown"}',
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.correctionRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    errorMessage.value!,
                    style: const TextStyle(color: AppColors.correctionRed, fontSize: 13),
                  ),
                ),
              ),

            if (isSubmitting.value)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
              ),

            // ── Provider Options ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: availableProviders.map((option) {
                  final name = option.$1;
                  final provider = option.$2;
                  final icon = option.$3;
                  final isCurrent = currentProvider == name.toLowerCase();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (isCurrent || isSubmitting.value)
                            ? null
                            : () => handleSwitch(provider, name),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppColors.starGold.withValues(alpha: 0.1)
                                : const Color(0x1AFFFFFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrent ? AppColors.starGold : const Color(0x1AFFFFFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(icon, color: AppColors.starGold),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: AppColors.universe.textStarlight,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                const Icon(Icons.check_circle, color: AppColors.starGold, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                '※ Changing your login method will update your authentication settings. You can switch back anytime.',
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
