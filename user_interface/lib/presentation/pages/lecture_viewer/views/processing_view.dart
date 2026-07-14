import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/processing_task.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/views/pipeline_steps_list.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';

/// 分析中(RUNNING/PENDING)とAnalysis Failed(FAILED)の両方を1つのウィジェットで
/// 描画する。両者はヘッダーの色/文言とStart Overボタンの見せ方が違うだけで、
/// 中身のステップ内訳(PipelineStepsList)は完全に共通のため。
class ProcessingView extends HookConsumerWidget {
  const ProcessingView({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(lectureId));
    final job = jobAsync.value;
    final jobFailed = job?.status == 'FAILED';

    final tasksAsync = job == null
        ? const AsyncValue<List<ProcessingTask>>.data([])
        : ref.watch(jobTasksStreamProvider(job.id));
    final tasks = tasksAsync.asData?.value ?? const <ProcessingTask>[];

    final total = tasks.isEmpty ? processingTaskOrder.length : tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;

    final themeColor = jobFailed ? AppColors.correctionRed : AppColors.starGold;

    final restartState = useState(false);

    Future<void> startOver() async {
      final confirm = await showCustomDialog(
        context: context,
        title: 'Start Over?',
        message:
            'This restarts the whole analysis from scratch. Progress that\'s already completed will be discarded.',
        confirmLabel: 'Start Over',
        icon: Icons.refresh,
        isDestructive: true,
      );
      if (confirm != true) return;

      restartState.value = true;
      try {
        await ref.read(lectureControllerProvider.notifier).startAnalysis(lectureId);
      } finally {
        if (context.mounted) restartState.value = false;
      }
    }

    return Container(
      color: AppColors.universe.voidBackground,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onLongPress: (!jobFailed && !restartState.value) ? startOver : null,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          value: total > 0 ? completed / total : null,
                          backgroundColor: AppColors.universe.glassWhiteLow,
                          valueColor: AlwaysStoppedAnimation(themeColor),
                        ),
                      ),
                      Icon(
                        jobFailed ? Icons.error_outline : Icons.auto_awesome,
                        color: themeColor,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                jobFailed ? 'Analysis Failed' : 'Analyzing Lecture...',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$completed / $total steps completed',
                style: TextStyle(
                  color: themeColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!jobFailed) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Hold the icon above to start over from scratch.',
                    style: TextStyle(
                      color: AppColors.universe.textComet.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: TextButton.icon(
                    onPressed: restartState.value ? null : startOver,
                    icon: restartState.value
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(restartState.value ? 'Starting over...' : 'Start over from scratch'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.universe.textComet),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PipelineStepsList(tasks: tasks, jobFailed: jobFailed),
            ],
          ),
        ),
      ),
    );
  }
}
