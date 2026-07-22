// lib/presentation/pages/sign_up/sign_up_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';
import 'package:lecture_companion_ui/presentation/widgets/password_strength_meter.dart';
import 'package:lecture_companion_ui/presentation/widgets/social_sign_in_button.dart';

class SignUpPage extends HookConsumerWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usernameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();

    final agreedToTerms = useState(false);
    final obscurePassword = useState(true);
    final obscureConfirmPassword = useState(true);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final inlineError = useState<dynamic>(null);

    final authState = ref.watch(authControllerProvider);

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created! Please check your email to verify.'),
              backgroundColor: AppColors.starGold,
            ),
          );
          context.go(AppRoutes.onboarding);
        },
        error: (error, stackTrace) {
          AppErrorDialog.showSmartNamed(
            context,
            actionName: 'creating your account',
            rawError: error,
            onFriendlyError: (err) {
              inlineError.value = err;
            },
          );
        },
      );
    });

    void signUp() {
      inlineError.value = null;
      if (formKey.currentState!.validate() && agreedToTerms.value) {
        ref.read(authControllerProvider.notifier).signUp(
          username: usernameController.text.trim(),
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      } else if (!agreedToTerms.value) {
        inlineError.value = 'Please agree to the Terms and Conditions';
      }
    }

    void signInWithGoogle() {
      ref.read(authControllerProvider.notifier).signInWithGoogle();
    }

    void signInWithApple() {
      ref.read(authControllerProvider.notifier).signInWithApple();
    }

    InputDecoration inputDecoration(String label, IconData icon, {Widget? suffixIcon}) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        prefixIcon: Icon(icon, color: AppColors.universe.textComet),
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
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.correctionRed, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      );
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
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
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
                      child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Join leFture',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.universe.textStarlight,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start your learning journey today',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.universe.textComet,
                        ),
                  ),
                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.universe.glassWhiteLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.universe.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (inlineError.value != null) ...[
                          AppErrorBox(
                            actionName: 'creating your account',
                            rawError: inlineError.value,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // ユーザーネーム
                        TextFormField(
                          controller: usernameController,
                          style: TextStyle(color: AppColors.universe.textStarlight),
                          cursorColor: AppColors.starGold,
                          decoration: inputDecoration('Username', Icons.person_outlined),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a username';
                            }
                            if (value.length < 3) {
                              return 'Username must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // メールアドレス
                        TextFormField(
                          controller: emailController,
                          style: TextStyle(color: AppColors.universe.textStarlight),
                          cursorColor: AppColors.starGold,
                          decoration: inputDecoration('Email', Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
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
                        const SizedBox(height: 16),

                        // パスワード
                        TextFormField(
                          controller: passwordController,
                          style: TextStyle(color: AppColors.universe.textStarlight),
                          cursorColor: AppColors.starGold,
                          decoration: inputDecoration(
                            'Password',
                            Icons.lock_outlined,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: AppColors.universe.textComet,
                              ),
                              onPressed: () => obscurePassword.value = !obscurePassword.value,
                            ),
                          ).copyWith(
                            helperText: 'At least 8 characters',
                            helperStyle: TextStyle(color: AppColors.universe.textComet),
                          ),
                          obscureText: obscurePassword.value,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        PasswordStrengthMeter(controller: passwordController),
                        const SizedBox(height: 16),

                        // パスワード確認
                        TextFormField(
                          controller: confirmPasswordController,
                          style: TextStyle(color: AppColors.universe.textStarlight),
                          cursorColor: AppColors.starGold,
                          decoration: inputDecoration(
                            'Confirm Password',
                            Icons.lock_outlined,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirmPassword.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: AppColors.universe.textComet,
                              ),
                              onPressed: () => obscureConfirmPassword.value = !obscureConfirmPassword.value,
                            ),
                          ),
                          obscureText: obscureConfirmPassword.value,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // 利用規約チェックボックス
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: agreedToTerms.value,
                              activeColor: AppColors.starGold,
                              checkColor: Colors.white,
                              side: BorderSide(color: AppColors.universe.glassBorder, width: 2),
                              onChanged: (value) {
                                agreedToTerms.value = value ?? false;
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: AppColors.universe.textComet,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      const TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                        text: 'Terms and Conditions',
                                        style: const TextStyle(
                                          color: AppColors.starGold,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => context.push(AppRoutes.termsOfService),
                                      ),
                                      const TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: const TextStyle(
                                          color: AppColors.starGold,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => context.push(AppRoutes.privacyPolicy),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // サインアップボタン
                        authState.isLoading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
                              )
                            : ElevatedButton(
                                onPressed: signUp,
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
                                  'Create Account',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                        const SizedBox(height: 20),
                        const AuthDivider(),
                        const SizedBox(height: 20),
                        SocialSignInButton(
                          provider: SocialProvider.google,
                          onPressed: signInWithGoogle,
                        ),
                        const SizedBox(height: 12),
                        SocialSignInButton(
                          provider: SocialProvider.apple,
                          onPressed: signInWithApple,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 15,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
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
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
