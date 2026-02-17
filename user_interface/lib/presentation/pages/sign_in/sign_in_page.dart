// lib/presentation/pages/auth/sign_in_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class SignInPage extends HookConsumerWidget {
  const SignInPage({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    
    final authState = ref.watch(authControllerProvider);
    
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) => context.go(AppRoutes.home),
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: AppColors.correctionRed,
            ),
          );
        },
      );
    });
    
    void signIn() {
      ref.read(authControllerProvider.notifier).signIn(
        emailController.text.trim(),
        passwordController.text,
      );
    }

    // 共通のInputDecorationスタイル
    InputDecoration inputDecoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        prefixIcon: Icon(icon, color: AppColors.universe.textComet),
        filled: true,
        fillColor: AppColors.universe.glassWhiteLow,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.starGold),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }
  
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        title: Text('Sign In', style: TextStyle(color: AppColors.universe.textStarlight)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: emailController,
              style: TextStyle(color: AppColors.universe.textStarlight),
              cursorColor: AppColors.starGold,
              decoration: inputDecoration('Email', Icons.email_outlined),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              style: TextStyle(color: AppColors.universe.textStarlight),
              cursorColor: AppColors.starGold,
              decoration: inputDecoration('Password', Icons.lock_outlined),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            authState.isLoading
                ? const CircularProgressIndicator(color: AppColors.starGold)
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.starGold,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(color: AppColors.universe.textComet),
                          ),
                          TextButton(
                            onPressed: () => context.push(AppRoutes.signUp),
                            child: const Text(
                              'Create Account',
                              style: TextStyle(color: AppColors.starGold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}