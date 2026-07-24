import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/domain/exceptions/insufficient_credits_exception.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class NotStartedView extends ConsumerWidget {
  const NotStartedView({super.key, required this.lecture});

  final Lecture lecture;

  void _showInsufficientCreditsDialog(
    BuildContext context,
    AppLocalizations l10n,
    InsufficientCreditsException error,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          error.isNoAllocation
              ? l10n.notStartedNoActivePlanTitle
              : l10n.notStartedOutOfCreditsTitle,
        ),
        content: Text(
          error.isNoAllocation
              ? l10n.notStartedNoAllocationMessage
              : l10n.notStartedOutOfCreditsMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.notStartedCancelButton),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push(AppRoutes.creditDetail);
            },
            child: Text(l10n.notStartedViewCreditsButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // クレジット不足/未加入エラーは、汎用のインラインエラー表示ではなく
    // 専用ダイアログでクレジットページへ誘導する。ref.listenなのでstateが
    // 変化した瞬間だけ発火し、rebuildのたびに再表示することはない。
    ref.listen<AsyncValue<void>>(lectureControllerProvider, (previous, next) {
      final error = next.error;
      if (error is InsufficientCreditsException) {
        _showInsufficientCreditsDialog(context, l10n, error);
      }
    });

    final controllerState = ref.watch(lectureControllerProvider);
    final isLoading = controllerState.isLoading;
    final hasCourse = lecture.courseId != null;
    final creditError = controllerState.error;
    final showInlineError = controllerState.hasError && creditError is! InsufficientCreditsException;

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
                l10n.notStartedReadyTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.notStartedReadySubtitle,
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
                              l10n.notStartedNoCourseWarning,
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
                          label: Text(l10n.notStartedChooseCourseButton),
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
                label: Text(
                  isLoading ? l10n.notStartedStartingLabel : l10n.notStartedStartAnalysisButton,
                ),
              ),
              if (showInlineError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    l10n.notStartedErrorPrefix(controllerState.error.toString()),
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
