// lib/presentation/pages/lecture_viewer/widgets/pipeline_progress_banner.dart
//
// 「もう一部の生成物は出来ている」状態(=FullScreenRevealBlurが剥がれた後)に
// 上部へ出す、控えめな進捗/エラーバナー。全画面を覆っていた旧ProcessingViewの
// 代わりに、既に見えているコンテンツを隠さず進捗だけを伝える役割。

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/lecture_viewer/views/pipeline_steps_list.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';

class PipelineProgressBanner extends HookConsumerWidget {
  const PipelineProgressBanner({
    super.key,
    required this.lectureId,
    required this.tasks,
    required this.jobFailed,
  });

  final String lectureId;
  final List<ProcessingTask> tasks;
  final bool jobFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final restarting = useState(false);

    final total = tasks.isEmpty ? processingTaskOrder.length : tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;
    final themeColor = jobFailed ? AppColors.correctionRed : AppColors.starGold;

    void showDetails() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PipelineDetailsSheet(
          lectureId: lectureId,
          initialTasks: tasks,
          initialJobFailed: jobFailed,
        ),
      );
    }

    Future<void> startOver() async {
      final confirm = await showCustomDialog(
        context: context,
        title: l10n.processingViewStartOverDialogTitle,
        message: l10n.processingViewStartOverDialogMessage,
        confirmLabel: l10n.processingViewStartOverConfirmButton,
        icon: Icons.refresh,
        isDestructive: true,
      );
      if (confirm != true) return;

      restarting.value = true;
      try {
        await ref.read(lectureControllerProvider.notifier).startAnalysis(lectureId, force: true);
      } finally {
        if (context.mounted) restarting.value = false;
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: showDetails,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: themeColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              if (jobFailed)
                Icon(Icons.error_outline, color: themeColor, size: 18)
              else
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: total > 0 ? completed / total : null,
                    color: themeColor,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  jobFailed
                      ? l10n.lectureViewerPartialFailureBanner
                      : l10n.processingViewStepsCompletedLabel(completed, total),
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (jobFailed)
                TextButton(
                  onPressed: restarting.value ? null : startOver,
                  style: TextButton.styleFrom(
                    foregroundColor: themeColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: restarting.value
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: themeColor),
                        )
                      : Text(l10n.processingViewStartOverConfirmButton),
                )
              else
                Icon(Icons.chevron_right, color: themeColor.withValues(alpha: 0.7), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineDetailsSheet extends StatelessWidget {
  const _PipelineDetailsSheet({
    required this.lectureId,
    required this.initialTasks,
    required this.initialJobFailed,
  });

  final String lectureId;
  final List<ProcessingTask> initialTasks;
  final bool initialJobFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.universe.voidBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                l10n.lectureViewerPipelineDetailsSheetTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Consumer(
                builder: (context, ref, _) {
                  final job = ref.watch(jobStreamProvider(lectureId)).asData?.value;
                  final tasks = job == null
                      ? initialTasks
                      : ref.watch(jobTasksStreamProvider(job.id)).asData?.value ?? initialTasks;
                  final jobFailed = job == null
                      ? initialJobFailed
                      : (job.status == 'FAILED' || job.status == 'ERROR');
                  return PipelineStepsList(tasks: tasks, jobFailed: jobFailed);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
