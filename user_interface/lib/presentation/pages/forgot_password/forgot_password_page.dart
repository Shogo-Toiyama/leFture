// lib/presentation/pages/forgot_password/forgot_password_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/infrastructure/repositories/backend_warmup.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';

class ForgotPasswordPage extends HookConsumerWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final emailController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSending = useState(false);
    final emailSent = useState(false);
    final statusMessage = useState<String?>(null);
    final inlineError = useState<dynamic>(null);

    // 画面が開いた瞬間にバックグラウンドでウォームアップ開始。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    // エラー発生時にダイアログで表示
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          isSending.value = false;
          statusMessage.value = null;
          AppErrorDialog.showSmartNamed(
            context,
            actionName: 'sending password reset link',
            rawError: error,
            onFriendlyError: (err) {
              inlineError.value = err;
            },
          );
        },
      );
    });

    Future<void> sendResetLink() async {
      if (!formKey.currentState!.validate()) return;
      isSending.value = true;
      inlineError.value = null;

      try {
        statusMessage.value = l10n.forgotPasswordStatusWaking;
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          isSending.value = false;
          statusMessage.value = null;
          if (context.mounted) {
            AppErrorDialog.showSmartNamed(
              context,
              actionName: 'sending password reset link',
              rawError: l10n.forgotPasswordErrorSlowServer,
              onFriendlyError: (err) {
                inlineError.value = err;
              },
            );
          }
          return;
        }
        statusMessage.value = l10n.forgotPasswordStatusSending;

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
                          emailSent.value ? l10n.forgotPasswordSuccessTitle : l10n.forgotPasswordTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.universe.textStarlight,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emailSent.value
                              ? l10n.forgotPasswordSuccessMessage(emailController.text.trim())
                              : l10n.forgotPasswordSubtitle,
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
                                      child: Text(l10n.forgotPasswordRetryButton),
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
                                      child: Text(
                                        l10n.forgotPasswordHaveLinkButton,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                  ],
                                )
                              : Form(
                                  key: formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (inlineError.value != null) ...[
                                        AppErrorBox(
                                          actionName: 'sending password reset link',
                                          rawError: inlineError.value,
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      TextFormField(
                                        controller: emailController,
                                        style: TextStyle(color: AppColors.universe.textStarlight),
                                        cursorColor: AppColors.starGold,
                                        keyboardType: TextInputType.emailAddress,
                                        decoration: InputDecoration(
                                          labelText: l10n.emailLabel,
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
                                            return l10n.authErrorEmailRequired;
                                          }
                                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                            return l10n.authErrorEmailInvalid;
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
                                              child: Text(
                                                l10n.sendResetLinkButton,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.rememberedPasswordPrompt,
                              style: TextStyle(
                                color: AppColors.universe.textComet,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: () => context.pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
