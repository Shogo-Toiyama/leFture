import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/profile/user_profile_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// プロフィール作成/編集用ボトムシート。
///
/// 本来はAIとの対話でユーザーの興味・目標を深掘りしたいが、その機能が
/// 出来るまでの間は、直接テキストで入力してもらう簡易フォームにしている。
class MakeProfileSheet extends HookConsumerWidget {
  const MakeProfileSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existing = ref.read(currentUserProfileProvider).asData?.value;

    final usernameCtl = useTextEditingController(text: existing?.username ?? '');
    final bioCtl = useTextEditingController(text: existing?.bio ?? '');
    final interestsCtl = useTextEditingController(text: existing?.interests ?? '');
    final futureGoalsCtl = useTextEditingController(text: existing?.futureGoals ?? '');
    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    // テキスト入力に応じてアバター内のイニシャルを動的に更新するためのフック
    useListenable(usernameCtl);

    final currentUsername = usernameCtl.text.trim();
    final avatarInitials = currentUsername.isEmpty
        ? 'EX'
        : currentUsername
            .split(' ')
            .where((e) => e.isNotEmpty)
            .map((e) => e[0].toUpperCase())
            .take(2)
            .join('');

    Future<void> submit() async {
      final bio = bioCtl.text.trim();
      if (bio.isEmpty) {
        errorMsg.value = 'Tell us a little about yourself first';
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

        ref.invalidate(currentUserProfileProvider);

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
                'Make Your Profile',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This helps leFture personalize your fun facts and study material.',
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // ── Avatar Edit Placeholder ────────────────────────
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF7C83FD), Color(0xFFFFB300)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          avatarInitials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 26,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.starGold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Change Avatar (Coming Soon)',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _ProfileTextField(
                controller: usernameCtl,
                label: 'Username',
                hint: 'e.g. Shogo',
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: bioCtl,
                label: 'About You *',
                hint: 'Who are you, what do you study, how do you like to learn?',
                icon: Icons.person_outline,
                maxLines: 4,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: interestsCtl,
                label: 'Interests',
                hint: 'e.g. astronomy, guitar, history',
                icon: Icons.auto_awesome_outlined,
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              _ProfileTextField(
                controller: futureGoalsCtl,
                label: 'Future Dreams',
                hint: 'What are you working toward?',
                icon: Icons.flag_outlined,
                maxLines: 2,
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
                      : const Text(
                          'Save Profile',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
