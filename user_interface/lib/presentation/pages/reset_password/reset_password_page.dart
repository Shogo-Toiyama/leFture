// lib/presentation/pages/reset_password/reset_password_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';
import 'package:lecture_companion_ui/presentation/widgets/auth_result_view.dart';
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
    final inlineError = useState<dynamic>(null);

    // リンク自体が無効/期限切れの場合、router.dartがクエリパラメータで
    // エラーを渡してくる。この場合はフォームを出さず、専用の結果画面を表示する。
    final linkError = GoRouterState.of(context).uri.queryParameters['error'];
    if (linkError != null) {
      return AuthResultView(
        success: false,
        icon: Icons.error_outline_rounded,
        title: 'Link invalid or expired',
        message: linkError,
        buttonLabel: 'Request a New Link',
        onButtonPressed: () => context.go(AppRoutes.forgotPassword),
      );
    }

    // エラー発生時にダイアログで表示
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          isSubmitting.value = false;
          AppErrorDialog.showSmartNamed(
            context,
            actionName: 'updating your password',
            rawError: error,
            onFriendlyError: (err) {
              inlineError.value = err;
            },
          );
        },
      );
    });

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      isSubmitting.value = true;
      inlineError.value = null;
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

    if (resetComplete.value) {
      return AuthResultView(
        success: true,
        icon: Icons.check_rounded,
        title: 'Password updated',
        message: 'Your password has been updated successfully. You\'re all set!',
        buttonLabel: 'Go to Dashboard',
        onButtonPressed: () => context.go(AppRoutes.home),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
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
                      gradient: const LinearGradient(
                        colors: [AppColors.starGold, AppColors.deepGold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.starGold.withValues(alpha: 0.35),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.key_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Set a new password',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.universe.textStarlight,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your new password must be different from previously used passwords',
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
                  child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (inlineError.value != null) ...[
                                AppErrorBox(
                                  actionName: 'updating your password',
                                  rawError: inlineError.value,
                                ),
                                const SizedBox(height: 16),
                              ],
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
