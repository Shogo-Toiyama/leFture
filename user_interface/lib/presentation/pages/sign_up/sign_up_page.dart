// lib/presentation/pages/sign_up/sign_up_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';
import 'package:lefture/presentation/widgets/password_strength_meter.dart';
import 'package:lefture/presentation/widgets/social_sign_in_button.dart';

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
    final isEmailExpanded = useState(false);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final inlineError = useState<dynamic>(null);

    final authState = ref.watch(authControllerProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.signUpSuccessSnackbar),
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
        inlineError.value = l10n.signUpErrorAgreeTerms;
      }
    }

    // Google/Appleでの登録前も、ユーザーネーム・チェックボックスは
    // Email登録と同じく必須にする。アコーディオンが閉じている間はEmail/Password
    // のTextFormFieldがツリーに存在しないため、ここでのvalidate()は
    // ユーザーネーム欄のみを検証する。
    bool validateUsernameAndTerms() {
      inlineError.value = null;
      if (!formKey.currentState!.validate()) {
        return false;
      }
      if (!agreedToTerms.value) {
        inlineError.value = l10n.signUpErrorAgreeTerms;
        return false;
      }
      return true;
    }

    void signInWithGoogle() {
      if (!validateUsernameAndTerms()) return;
      ref.read(authControllerProvider.notifier).signInWithGoogle(
        desiredUsername: usernameController.text.trim(),
      );
    }

    void signInWithApple() {
      if (!validateUsernameAndTerms()) return;
      ref.read(authControllerProvider.notifier).signInWithApple(
        desiredUsername: usernameController.text.trim(),
      );
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 440,
                      minHeight: (constraints.maxHeight - 64) > 0 ? (constraints.maxHeight - 64) : 0,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                            l10n.signUpTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.universe.textStarlight,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.signUpSubtitle,
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
                                // ユーザーネーム(どのサインアップ方法でも必須)
                                TextFormField(
                                  controller: usernameController,
                                  style: TextStyle(color: AppColors.universe.textStarlight),
                                  cursorColor: AppColors.starGold,
                                  decoration: inputDecoration(l10n.usernameLabel, Icons.person_outlined),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l10n.signUpErrorUsernameEmpty;
                                    }
                                    if (value.length < 3) {
                                      return l10n.signUpErrorUsernameTooShort;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),

                                // 利用規約チェックボックス(どのサインアップ方法でも必須)
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
                                              TextSpan(text: l10n.signUpAgreementPrefix),
                                              TextSpan(
                                                text: l10n.termsAndConditionsLink,
                                                style: const TextStyle(
                                                  color: AppColors.starGold,
                                                  decoration: TextDecoration.underline,
                                                ),
                                                recognizer: TapGestureRecognizer()
                                                  ..onTap = () => context.push(AppRoutes.termsOfService),
                                              ),
                                              TextSpan(text: l10n.signUpAgreementMiddle),
                                              TextSpan(
                                                text: l10n.privacyPolicyLink,
                                                style: const TextStyle(
                                                  color: AppColors.starGold,
                                                  decoration: TextDecoration.underline,
                                                ),
                                                recognizer: TapGestureRecognizer()
                                                  ..onTap = () => context.push(AppRoutes.privacyPolicy),
                                              ),
                                              TextSpan(text: l10n.signUpAgreementSuffix),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Google/Apple/Emailの3つを対等な選択肢として並べる
                                SocialSignInButton(
                                  provider: SocialProvider.google,
                                  onPressed: signInWithGoogle,
                                ),
                                const SizedBox(height: 12),
                                SocialSignInButton(
                                  provider: SocialProvider.apple,
                                  onPressed: signInWithApple,
                                ),
                                const SizedBox(height: 12),
                                SocialSignInButton(
                                  provider: SocialProvider.email,
                                  onPressed: () => isEmailExpanded.value = !isEmailExpanded.value,
                                ),

                                // アコーディオン: 「Continue with email」がタップされた時だけ、
                                // Email/Password欄一式とサインアップ実行ボタンを表示する。
                                // Visibilityではなくツリーからの出し入れにしている
                                // (閉じている間はvalidatorが存在せず、ユーザーネームだけの
                                // 検証で済むようにするため)。
                                if (isEmailExpanded.value) ...[
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: emailController,
                                    style: TextStyle(color: AppColors.universe.textStarlight),
                                    cursorColor: AppColors.starGold,
                                    decoration: inputDecoration(l10n.emailLabel, Icons.email_outlined),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.authErrorEmailRequired;
                                      }
                                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                        return l10n.authErrorEmailInvalid;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: passwordController,
                                    style: TextStyle(color: AppColors.universe.textStarlight),
                                    cursorColor: AppColors.starGold,
                                    decoration: inputDecoration(
                                      l10n.passwordLabel,
                                      Icons.lock_outlined,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          obscurePassword.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                          color: AppColors.universe.textComet,
                                        ),
                                        onPressed: () => obscurePassword.value = !obscurePassword.value,
                                      ),
                                    ).copyWith(
                                      helperText: l10n.passwordReqMinLength,
                                      helperStyle: TextStyle(color: AppColors.universe.textComet),
                                    ),
                                    obscureText: obscurePassword.value,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.signUpErrorPasswordEmpty;
                                      }
                                      if (value.length < 8) {
                                        return l10n.passwordErrorTooShort;
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
                                    decoration: inputDecoration(
                                      l10n.confirmPasswordLabel,
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
                                        return l10n.confirmPasswordErrorEmpty;
                                      }
                                      if (value != passwordController.text) {
                                        return l10n.passwordsMismatchError;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
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
                                          child: Text(
                                            l10n.signUpSubmitButton,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.signUpHasAccountPrompt,
                                style: TextStyle(
                                  color: AppColors.universe.textComet,
                                  fontSize: 15,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  // 通常はSignInPageからpushされてくるのでpopで戻れるが、
                                  // Introduction(サインアップ前の3枚)のCTAからはgo()で
                                  // 直接遷移してくる(スタックにSignInが無い)ため、
                                  // popできる場合だけpopし、できなければsignInへ遷移する。
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go(AppRoutes.signIn);
                                  }
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  l10n.signInLink,
                                  style: const TextStyle(
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
            },
          ),
        ),
      ),
    );
  }
}
