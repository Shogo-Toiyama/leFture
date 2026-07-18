// lib/presentation/pages/reset_password/reset_password_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/password_strength_meter.dart';

/// メール内のリセットリンクをクリックした後にユーザーが着地するページ。
/// Recovery セッション内で supabase.auth.updateUser を呼び出して新パスワードを確定する。
class ResetPasswordPage extends HookConsumerWidget {
  const ResetPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passwordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    final obscurePassword = useState(true);
    final obscureConfirmPassword = useState(true);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSubmitting = useState(false);
    final resetComplete = useState(false);

    // エラー・成功時のハンドリング
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          isSubmitting.value = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: AppColors.correctionRed,
            ),
          );
        },
      );
    });

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      isSubmitting.value = true;
      await ref
          .read(authControllerProvider.notifier)
          .updatePassword(passwordController.text);
      if (context.mounted) {
        isSubmitting.value = false;
        resetComplete.value = true;
      }
    }

    InputDecoration inputDecoration(String label, {required Widget suffixIcon}) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        prefixIcon: Icon(Icons.lock_outlined, color: AppColors.universe.textComet),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.universe.glassWhiteLow,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.starGold, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.correctionRed),
          borderRadius: BorderRadius.circular(14),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !resetComplete.value,
        leading: resetComplete.value
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.9),
            radius: 1.4,
            colors: [
              AppColors.deepGold.withValues(alpha: 0.16),
              AppColors.universe.voidBackground,
            ],
            stops: const [0, 0.7],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: resetComplete.value
                            ? [AppColors.growthGreen, AppColors.growthGreen.withValues(alpha: 0.7)]
                            : const [AppColors.starGold, AppColors.deepGold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (resetComplete.value ? AppColors.growthGreen : AppColors.starGold)
                              .withValues(alpha: 0.35),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      resetComplete.value ? Icons.check_rounded : Icons.key_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  resetComplete.value ? 'Password updated' : 'Set a new password',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.universe.textStarlight,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  resetComplete.value
                      ? 'Your password has been updated successfully. You\'re all set!'
                      : 'Your new password must be different from previously used passwords',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.universe.textComet,
                      ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: resetComplete.value
                      ? ElevatedButton(
                          onPressed: () => context.go(AppRoutes.home),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.starGold,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Go to Dashboard',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        )
                      : Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: passwordController,
                                style: TextStyle(color: AppColors.universe.textStarlight),
                                cursorColor: AppColors.starGold,
                                obscureText: obscurePassword.value,
                                decoration: inputDecoration(
                                  'New Password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscurePassword.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: AppColors.universe.textComet,
                                    ),
                                    onPressed: () => obscurePassword.value = !obscurePassword.value,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter a new password';
                                  }
                                  if (value.length < 8) {
                                    return 'Password must be at least 8 characters';
                                  }
                                  return null;
                                },
                              ),
                              PasswordStrengthMeter(controller: passwordController),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: confirmPasswordController,
                                style: TextStyle(color: AppColors.universe.textStarlight),
                                cursorColor: AppColors.starGold,
                                obscureText: obscureConfirmPassword.value,
                                decoration: inputDecoration(
                                  'Confirm New Password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureConfirmPassword.value
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: AppColors.universe.textComet,
                                    ),
                                    onPressed: () => obscureConfirmPassword.value = !obscureConfirmPassword.value,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your new password';
                                  }
                                  if (value != passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              isSubmitting.value
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
                                    )
                                  : ElevatedButton(
                                      onPressed: submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.starGold,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        minimumSize: const Size(double.infinity, 52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: const Text(
                                        'Reset Password',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                            ],
                          ),
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
