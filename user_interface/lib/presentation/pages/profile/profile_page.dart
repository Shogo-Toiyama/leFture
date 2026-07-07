import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/debug/debug_providers.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      context.go(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceEmptyHome = ref.watch(debugForceEmptyHomeProvider);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        title: Text(
          'Profile',
          style: TextStyle(color: AppColors.universe.textStarlight),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          // デバッグ用の設定セクション
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'DEBUG SETTINGS',
              style: TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report, color: AppColors.starGold),
            title: const Text(
              'Force Empty Home',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Forces HomePage to show the Empty (Onboarding) state.',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
            value: forceEmptyHome,
            activeThumbColor: AppColors.starGold,
            onChanged: (val) {
              ref.read(debugForceEmptyHomeProvider.notifier).toggle(val);
            },
          ),
          const Divider(color: Colors.white10),

          // ログアウトボタンは赤色（correctionRed）で警告感を出す
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.correctionRed),
            title: const Text(
              'Sign Out',
              style: TextStyle(color: AppColors.correctionRed),
            ),
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}