import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class NotStartedView extends ConsumerWidget {
  const NotStartedView({super.key, required this.lecture});

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(lectureControllerProvider);
    final isLoading = controllerState.isLoading;
    final hasCourse = lecture.courseId != null;

    Future<void> assignCourse() async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LectureEditSheet(lecture: lecture),
      );
    }

    return Container(
      color: AppColors.universe.voidBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.starGold.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.auto_awesome, size: 40, color: AppColors.starGold),
              ),
              const SizedBox(height: 28),
              Text(
                'Ready to Analyze',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The audio is ready. Generate transcript, summary, and notes with AI.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
              ),
              if (!hasCourse) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.alertAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.alertAmber.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.alertAmber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "This lecture isn't assigned to a course yet. Analysis can't start until it is.",
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: assignCourse,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.alertAmber,
                            side: BorderSide(color: AppColors.alertAmber.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: const Text('Choose Course'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: (isLoading || !hasCourse)
                    ? null
                    : () {
                        ref.read(lectureControllerProvider.notifier).startAnalysis(lecture.id);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.starGold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                  disabledForegroundColor: AppColors.universe.textComet,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(isLoading ? 'Starting...' : 'Start Analysis'),
              ),
              if (controllerState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Error: ${controllerState.error}',
                    style: const TextStyle(color: AppColors.correctionRed),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
