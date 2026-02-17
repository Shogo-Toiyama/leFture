// lib/presentation/pages/auth/sign_up_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class SignUpPage extends HookConsumerWidget {
  const SignUpPage({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usernameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    
    final agreedToTerms = useState(false);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    
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
          context.go(AppRoutes.home);
        },
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
    
    void signUp() {
      if (formKey.currentState!.validate() && agreedToTerms.value) {
        ref.read(authControllerProvider.notifier).signUp(
          username: usernameController.text.trim(),
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      } else if (!agreedToTerms.value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please agree to the Terms and Conditions'),
            backgroundColor: AppColors.alertAmber,
          ),
        );
      }
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
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.correctionRed),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.correctionRed),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        title: Text('Create Account', style: TextStyle(color: AppColors.universe.textStarlight)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'Join leFture',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.universe.textStarlight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your learning journey today',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.universe.textComet,
                  ),
                ),
                const SizedBox(height: 32),
                
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
                  decoration: inputDecoration('Password', Icons.lock_outlined).copyWith(
                    helperText: 'At least 8 characters',
                    helperStyle: TextStyle(color: AppColors.universe.textComet),
                  ),
                  obscureText: true,
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
                const SizedBox(height: 16),
                
                // パスワード確認
                TextFormField(
                  controller: confirmPasswordController,
                  style: TextStyle(color: AppColors.universe.textStarlight),
                  cursorColor: AppColors.starGold,
                  decoration: inputDecoration('Confirm Password', Icons.lock_outlined),
                  obscureText: true,
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
                const SizedBox(height: 24),
                
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
                                  ..onTap = () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Terms page - Coming soon'),
                                      ),
                                    );
                                  },
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: const TextStyle(
                                  color: AppColors.starGold,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Privacy Policy page - Coming soon'),
                                      ),
                                    );
                                  },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // サインアップボタン
                authState.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.starGold))
                    : ElevatedButton(
                        onPressed: signUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.starGold,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Create Account',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                const SizedBox(height: 16),
                
                // サインインページへ戻る
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: AppColors.universe.textComet),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(color: AppColors.starGold),
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