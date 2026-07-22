import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/backend_warmup.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';

class ChangePasswordSheet extends HookConsumerWidget {
  const ChangePasswordSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passwordController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());

    final obscurePassword = useState(true);
    final isSubmitting = useState(false);
    final isSuccess = useState(false);
    final errorMessage = useState<String?>(null);
    final statusMessage = useState<String?>(null);

    // シートが開いた瞬間にバックグラウンドでウォームアップ開始。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    final currentUser = supabase.auth.currentUser;
    final userEmail = currentUser?.email ?? '';

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;

      isSubmitting.value = true;
      errorMessage.value = null;

      try {
        // 1. Verify current password by signing in in the background
        // (直接呼び出しなので失敗時は例外を投げる → catch で捕捉される)
        await supabase.auth.signInWithPassword(
          email: userEmail,
          password: passwordController.text,
        );

        // Supabase の Send Email Hook はバックエンドの応答を5秒以内にしか
        // 待たない。開いた時点から進行中のウォームアップの完了(起動確認)を
        // 待ってから本番リクエストを送ることで、Cloud Runのコールドスタートに
        // よるタイムアウトを避ける。起動確認できなかった場合は、どうせ
        // 失敗するだけの本番リクエストを送らずここで止める。
        statusMessage.value = 'Waking up email service...';
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          errorMessage.value =
              'The email service is taking longer than usual to start. Please try again in a moment.';
          return;
        }
        statusMessage.value = 'Sending reset link...';

        // 2. Send password reset link to the verified email
        // sendPasswordReset は AsyncValue.guard で例外を握りつぶすため、
        // 戻り値の AsyncValue を見て成否を判定する(レート制限等で失敗しても
        // 成功扱いにならないように)。
        final result = await ref
            .read(authControllerProvider.notifier)
            .sendPasswordReset(userEmail);
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
        errorMessage.value = e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
      } finally {
        isSubmitting.value = false;
        statusMessage.value = null;
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
                        'Reset Link Sent',
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We have sent a password reset link to your email address ($userEmail). '
                        'Please check your inbox and click the link to set your new password.',
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
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  'Change Password',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your current password to verify your identity and send a reset link to your email.',
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (errorMessage.value != null) ...[
                  AppErrorBox(
                    actionName: 'updating your password',
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
                        controller: passwordController,
                        style: TextStyle(color: AppColors.universe.textStarlight),
                        cursorColor: AppColors.starGold,
                        obscureText: obscurePassword.value,
                        decoration: inputDecoration(
                          'Current Password',
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
                            return 'Please enter your current password';
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
                              child: const Text(
                                'Send Reset Link',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
