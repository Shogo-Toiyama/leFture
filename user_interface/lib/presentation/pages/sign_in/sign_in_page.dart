// lib/presentation/pages/sign_in/sign_in_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';
import 'package:lefture/presentation/widgets/language_header_button.dart';
import 'package:lefture/presentation/widgets/social_sign_in_button.dart';

class SignInPage extends HookConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final obscurePassword = useState(true);
    final inlineError = useState<dynamic>(null);

    final authState = ref.watch(authControllerProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          final session = supabase.auth.currentSession;
          if (session != null) {
            ref.read(lectureControllerProvider.notifier).resetThrottle();
            ref.invalidate(courseListProvider);
            context.go(AppRoutes.home);
          }
        },
        error: (error, stackTrace) {
          if (error.toString().contains('ACCOUNT_NOT_FOUND')) {
            inlineError.value = l10n.signInUserNotFoundMessage;
            return;
          }
          AppErrorDialog.showSmartNamed(
            context,
            actionName: 'signing in',
            rawError: error,
            onFriendlyError: (err) {
              inlineError.value = err;
            },
          );
        },
      );
    });

    void signIn() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      inlineError.value = null;
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (email.isEmpty) {
        inlineError.value = l10n.signInErrorEmailEmpty;
        return;
      }
      if (password.isEmpty) {
        inlineError.value = l10n.signInErrorPasswordEmpty;
        return;
      }

      ref.read(authControllerProvider.notifier).signIn(
        email,
        password,
      );
    }

    void signInWithGoogle() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      ref.read(authControllerProvider.notifier).signInWithGoogle();
    }

    void signInWithApple() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
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
      );
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.7),
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
                          child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
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
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 34),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.signInWelcomeTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.universe.textStarlight,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.signInSubtitle,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (inlineError.value != null) ...[
                                AppErrorBox(
                                  actionName: 'signing in',
                                  rawError: inlineError.value,
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextField(
                                controller: emailController,
                                style: TextStyle(color: AppColors.universe.textStarlight),
                                cursorColor: AppColors.starGold,
                                decoration: inputDecoration(l10n.emailLabel, Icons.email_outlined),
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 16),
                              TextField(
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
                                ),
                                obscureText: obscurePassword.value,
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => context.push(AppRoutes.forgotPassword),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    l10n.forgotPasswordLink,
                                    style: TextStyle(
                                      color: AppColors.universe.textComet,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              authState.isLoading
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
                                    )
                                  : ElevatedButton(
                                      onPressed: signIn,
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
                                        l10n.signInButton,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                              const SizedBox(height: 20),
                              AuthDivider(label: l10n.authDividerOr),
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
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.signInNoAccountPrompt,
                              style: TextStyle(
                                color: AppColors.universe.textComet,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.signUp),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                l10n.createAccountLink,
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
              );
            },
          ),
        ),
      ),
    ),
          Positioned(
            top: 4,
            right: 18,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: const LanguageHeaderButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
