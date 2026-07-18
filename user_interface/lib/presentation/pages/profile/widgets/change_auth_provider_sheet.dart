import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangeAuthProviderSheet extends ConsumerWidget {
  const ChangeAuthProviderSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final currentProvider = ref.read(authControllerProvider.notifier).getCurrentProvider();

    final availableProviders = [
      ('Email', OAuthProvider.google, Icons.email_outlined),
      ('Google', OAuthProvider.google, Icons.g_mobiledata),
      ('Apple', OAuthProvider.apple, Icons.apple),
    ];

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
                        onTap: isCurrent
                            ? null
                            : () {
                                ref.read(authControllerProvider.notifier).switchProvider(provider);
                                Navigator.of(context).pop();
                              },
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
