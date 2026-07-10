import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/processing_task.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';

class ProcessingView extends HookConsumerWidget {
  const ProcessingView({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(lectureId));
    final job = jobAsync.value;

    final tasksAsync = job == null
        ? const AsyncValue<List<ProcessingTask>>.data([])
        : ref.watch(jobTasksStreamProvider(job.id));
    final tasks = tasksAsync.asData?.value ?? const <ProcessingTask>[];

    final total = tasks.isEmpty ? processingTaskOrder.length : tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;
    final staleFailed = tasks.where((t) => t.isStaleFailed).toList();

    // ブループリント順で「今動いていそうな」タスクを1つ選ぶ（表示用）
    String? currentLabel;
    final byType = {for (final t in tasks) t.taskType: t};
    for (final type in processingTaskOrder) {
      final t = byType[type];
      if (t == null || (!t.isCompleted && !t.isCancelled && !t.isStaleFailed)) {
        currentLabel = processingTaskLabel(type);
        break;
      }
    }

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
                onLongPress: restartState.value ? null : startOver,
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
                          valueColor: const AlwaysStoppedAnimation(AppColors.starGold),
                        ),
                      ),
                      const Icon(Icons.auto_awesome, color: AppColors.starGold, size: 26),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Analyzing Lecture...',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$completed / $total steps completed',
                style: const TextStyle(
                  color: AppColors.starGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (currentLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  currentLabel,
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                ),
              ],
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
              if (staleFailed.isNotEmpty) ...[
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Needs attention',
                    style: TextStyle(
                      color: AppColors.correctionRed,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final task in staleFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StuckTaskCard(task: task),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StuckTaskCard extends HookConsumerWidget {
  const _StuckTaskCard({required this.task});

  final ProcessingTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRetrying = useState(false);
    final error = useState<String?>(null);

    Future<void> retry() async {
      isRetrying.value = true;
      error.value = null;
      try {
        await ref.read(jobRepositoryProvider).retryTask(taskId: task.id);
      } catch (e) {
        error.value = e.toString();
      } finally {
        if (context.mounted) isRetrying.value = false;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.correctionRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.correctionRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  processingTaskLabel(task.taskType),
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (error.value != null) ...[
            const SizedBox(height: 6),
            Text(
              error.value!,
              style: const TextStyle(color: AppColors.correctionRed, fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: isRetrying.value ? null : retry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.correctionRed,
                side: BorderSide(color: AppColors.correctionRed.withValues(alpha: 0.5)),
              ),
              icon: isRetrying.value
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.correctionRed),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(isRetrying.value ? 'Retrying...' : 'Retry this step'),
            ),
          ),
        ],
      ),
    );
  }
}
