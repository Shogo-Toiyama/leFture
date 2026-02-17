import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      context.go(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
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