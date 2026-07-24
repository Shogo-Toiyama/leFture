import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/backend_warmup.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/pending_auth_action.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';

class ChangeEmailSheet extends HookConsumerWidget {
  const ChangeEmailSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final emailController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSubmitting = useState(false);
    final isSuccess = useState(false);
    final errorMessage = useState<String?>(null);
    final statusMessage = useState<String?>(null);

    // シートが開いた瞬間にバックグラウンドでウォームアップ開始。
    // ユーザーが入力している間にコールドスタートの待ち時間を先に消化しておく。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    final currentUser = ref.watch(currentUserProvider);
    final currentEmail = currentUser?.email ?? '';

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;

      final newEmail = emailController.text.trim();
      if (newEmail == currentEmail) {
        errorMessage.value = l10n.changeEmailDifferentRequiredError;
        return;
      }

      isSubmitting.value = true;
      errorMessage.value = null;

      try {
        // Supabase の Send Email Hook はバックエンドの応答を5秒以内にしか
        // 待たない。開いた時点から進行中のウォームアップの完了(起動確認)を
        // 待ってから本番リクエストを送ることで、Cloud Runのコールドスタートに
        // よるタイムアウトを避ける。起動確認できなかった場合は、どうせ
        // 失敗するだけの本番リクエストを送らずここで止める。
        statusMessage.value = l10n.forgotPasswordStatusWaking;
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          errorMessage.value = l10n.changePasswordSlowServerError;
          return;
        }
        statusMessage.value = l10n.changeEmailSendingVerificationStatus;

        // deep linkコールバックだけでは「メールアドレス変更」由来だと判別できない
        // ケースに備え、リクエスト直前に待機中の操作を記録しておく。
        await setPendingAuthAction(PendingAuthActionKind.emailChange);

        // updateEmail は AsyncValue.guard で例外を握りつぶすため throw されない。
        // 戻り値の AsyncValue を見て成否を判定しないと、レート制限や
        // 「メールアドレス重複(422)」等で失敗しても成功扱いになってしまう。
        final result =
            await ref.read(authControllerProvider.notifier).updateEmail(newEmail);
        if (result.hasError) {
          errorMessage.value = result.error
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', '')
              .replaceAll('AuthApiException: ', '');
        } else {
          isSuccess.value = true;
        }
      } catch (e) {
        errorMessage.value = e.toString().replaceAll('Exception: ', '');
      } finally {
        isSubmitting.value = false;
        statusMessage.value = null;
      }
    }

    InputDecoration inputDecoration(String label) {
      return InputDecoration(
        labelText: label,
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
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF13131C), // Matching voidCard background
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              if (isSuccess.value) ...[
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.growthGreen.withValues(alpha: 0.15),
                          border: Border.all(color: AppColors.growthGreen, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.growthGreen,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.changeEmailVerificationSentTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.changeEmailVerificationSentMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
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
                          l10n.changePasswordCloseButton,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  l10n.changeEmailTitle,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.changeEmailCurrentEmailLabel(currentEmail),
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (errorMessage.value != null) ...[
                  AppErrorBox(
                    actionName: 'updating your email address',
                    rawError: errorMessage.value,
                  ),
                  const SizedBox(height: 16),
                ],
                Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: emailController,
                        style: TextStyle(color: AppColors.universe.textStarlight),
                        cursorColor: AppColors.starGold,
                        keyboardType: TextInputType.emailAddress,
                        decoration: inputDecoration(l10n.changeEmailNewLabel),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.changeEmailRequiredError;
                          }
                          final emailRegExp = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!emailRegExp.hasMatch(value.trim())) {
                            return l10n.changeEmailInvalidError;

                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),
                      isSubmitting.value
                          ? Center(
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
                              child: Text(
                                l10n.changeEmailConfirmButton,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
