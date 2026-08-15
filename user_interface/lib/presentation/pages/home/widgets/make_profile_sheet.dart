import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_avatar_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/user_avatar.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// プロフィール作成/編集用ボトムシート。
///
/// 本来はAIとの対話でユーザーの興味・目標を深掘りしたいが、その機能が
/// 出来るまでの間は、直接テキストで入力してもらう簡易フォームにしている。
class MakeProfileSheet extends HookConsumerWidget {
  const MakeProfileSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final existing = ref.watch(currentUserProfileProvider).asData?.value;

    final usernameCtl = useTextEditingController(text: existing?.username ?? '');
    final bioCtl = useTextEditingController(text: existing?.bio ?? '');
    final interestsCtl = useTextEditingController(text: existing?.interests ?? '');
    final futureGoalsCtl = useTextEditingController(text: existing?.futureGoals ?? '');
    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    Future<void> submit() async {
      final bio = bioCtl.text.trim();
      if (bio.isEmpty) {
        errorMsg.value = l10n.makeProfileBioEmptyError;
        return;
      }
      isSubmitting.value = true;
      errorMsg.value = null;
      try {
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.updateProfile(
          username: usernameCtl.text.trim().isEmpty ? null : usernameCtl.text.trim(),
          bio: bio,
          interests: interestsCtl.text.trim().isEmpty ? null : interestsCtl.text.trim(),
          futureGoals: futureGoalsCtl.text.trim().isEmpty ? null : futureGoalsCtl.text.trim(),
        );

        // Outboxに書き込まれた変更を即座に送信開始
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();

        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        errorMsg.value = e.toString();
      } finally {
        isSubmitting.value = false;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C2E),
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
              Text(
                l10n.makeProfileSheetTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.makeProfileSheetSubtitle,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // ── Avatar Edit ────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ChangeAvatarSheet(profile: existing),
                    );
                  },
                  child: Stack(
                    children: [
                      UserAvatar(profile: existing, size: 80),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.starGold,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1A1C2E),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _ProfileTextField(
                controller: usernameCtl,
                label: l10n.usernameLabel,
                hint: l10n.makeProfileUsernameHint,
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: bioCtl,
                label: l10n.makeProfileAboutYouLabel,
                hint: l10n.makeProfileAboutYouHint,
                icon: Icons.person_outline,
                minLines: 4,
                maxLines: 8,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: interestsCtl,
                label: l10n.makeProfileInterestsLabel,
                hint: l10n.makeProfileInterestsHint,
                icon: Icons.auto_awesome_outlined,
                minLines: 4,
                maxLines: 8,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: futureGoalsCtl,
                label: l10n.makeProfileFutureDreamsLabel,
                hint: l10n.makeProfileFutureDreamsHint,
                icon: Icons.flag_outlined,
                minLines: 4,
                maxLines: 8,
              ),

              if (errorMsg.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMsg.value!,
                  style: const TextStyle(color: AppColors.correctionRed, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting.value ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSubmitting.value
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          l10n.makeProfileSaveButton,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(color: AppColors.universe.textStarlight),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.5)),
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
      ),
    );
  }
}
