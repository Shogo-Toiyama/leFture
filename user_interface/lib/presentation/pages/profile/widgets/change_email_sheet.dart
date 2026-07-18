import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ChangeEmailSheet extends HookConsumerWidget {
  const ChangeEmailSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSubmitting = useState(false);
    final isSuccess = useState(false);
    final errorMessage = useState<String?>(null);

    final currentUser = ref.watch(currentUserProvider);
    final currentEmail = currentUser?.email ?? '';

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      
      final newEmail = emailController.text.trim();
      if (newEmail == currentEmail) {
        errorMessage.value = 'New email must be different from current email';
        return;
      }

      isSubmitting.value = true;
      errorMessage.value = null;

      try {
        await ref.read(authControllerProvider.notifier).updateEmail(newEmail);
        
        // Supabase returns the updated user model, but it requires email verification.
        // If we reach here without error, the update request was sent successfully.
        isSuccess.value = true;
      } catch (e) {
        errorMessage.value = e.toString().replaceAll('Exception: ', '');
      } finally {
        isSubmitting.value = false;
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
                        'Verification Email Sent',
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'A verification link has been sent to both your current email and new email. '
                        'Please verify the change from both boxes to complete the update.',
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
                  'Change Email',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your current email address is $currentEmail',
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (errorMessage.value != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.correctionRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      errorMessage.value!,
                      style: const TextStyle(color: AppColors.correctionRed, fontSize: 13),
                    ),
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
                        decoration: inputDecoration('New Email Address'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a new email';
                          }
                          final emailRegExp = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!emailRegExp.hasMatch(value.trim())) {
                            return 'Please enter a valid email address';
                            
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),
                      isSubmitting.value
                          ? const Center(
                              child: CircularProgressIndicator(color: AppColors.starGold),
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
                                'Confirm Change',
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
