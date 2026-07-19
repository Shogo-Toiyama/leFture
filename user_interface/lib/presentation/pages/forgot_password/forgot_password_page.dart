// lib/presentation/pages/forgot_password/forgot_password_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/backend_warmup.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ForgotPasswordPage extends HookConsumerWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSending = useState(false);
    final emailSent = useState(false);
    final statusMessage = useState<String?>(null);

    // 画面が開いた瞬間にバックグラウンドでウォームアップ開始。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    // エラー発生時にスナックバーで表示
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          isSending.value = false;
          statusMessage.value = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: AppColors.correctionRed,
            ),
          );
        },
      );
    });

    Future<void> sendResetLink() async {
      if (!formKey.currentState!.validate()) return;
      isSending.value = true;

      try {
        statusMessage.value = 'Waking up email service...';
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          isSending.value = false;
          statusMessage.value = null;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The email service is taking longer than usual to start. Please try again in a moment.',
                ),
                backgroundColor: AppColors.correctionRed,
              ),
            );
          }
          return;
        }
        statusMessage.value = 'Sending reset link...';

        await ref
            .read(authControllerProvider.notifier)
            .sendPasswordReset(emailController.text.trim());
        // エラー時は ref.listen が処理するため、ここでは成功扱いにする
        if (context.mounted) {
          isSending.value = false;
          emailSent.value = true;
        }
      } finally {
        statusMessage.value = null;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
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
                        colors: emailSent.value
                            ? [AppColors.growthGreen, AppColors.growthGreen.withValues(alpha: 0.7)]
                            : const [AppColors.starGold, AppColors.deepGold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (emailSent.value ? AppColors.growthGreen : AppColors.starGold)
                              .withValues(alpha: 0.35),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      emailSent.value ? Icons.mark_email_read_rounded : Icons.lock_reset_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  emailSent.value ? 'Check your email' : 'Forgot password?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.universe.textStarlight,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  emailSent.value
                      ? "We've sent a password reset link to ${emailController.text.trim()}"
                      : "No worries, enter your email and we'll send you a reset link",
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
                  child: emailSent.value
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                emailSent.value = false;
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.universe.textStarlight,
                                side: BorderSide(color: AppColors.universe.glassBorder),
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("Didn't get it? Try again"),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => context.push(AppRoutes.resetPassword),
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
                                'I have a reset link',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        )
                      : Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: emailController,
                                style: TextStyle(color: AppColors.universe.textStarlight),
                                cursorColor: AppColors.starGold,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(color: AppColors.universe.textComet),
                                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.universe.textComet),
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
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              isSending.value
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: Column(
                                          children: [
                                            const CircularProgressIndicator(color: AppColors.starGold),
                                            if (statusMessage.value != null) ...[
                                              const SizedBox(height: 12),
                                              Text(
                                                statusMessage.value!,
                                                style: TextStyle(
                                                  color: AppColors.universe.textComet,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: sendResetLink,
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
                                        'Send Reset Link',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Remembered your password? ',
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 15,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: AppColors.starGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
