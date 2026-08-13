import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/lecture_viewer/views/pipeline_steps_list.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';

/// 分析中(RUNNING/PENDING)とAnalysis Failed(FAILED)の両方を1つのウィジェットで
/// 描画する。両者はヘッダーの色/文言とStart Overボタンの見せ方が違うだけで、
/// 中身のステップ内訳(PipelineStepsList)は完全に共通のため。
class ProcessingView extends HookConsumerWidget {
  const ProcessingView({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final jobAsync = ref.watch(jobStreamProvider(lectureId));
    final job = jobAsync.value;
    // ERRORは旧pipeline.py(JobStatus.ERROR)が書く失敗ステータス。FAILEDと同じく
    // 「失敗」として扱わないと、Start Overが出ないまま解析中の見た目で止まる。
    final jobFailed = job?.status == 'FAILED' || job?.status == 'ERROR';

    final tasksAsync = job == null
        ? const AsyncValue<List<ProcessingTask>>.data([])
        : ref.watch(jobTasksStreamProvider(job.id));
    final tasks = tasksAsync.asData?.value ?? const <ProcessingTask>[];

    final total = tasks.isEmpty ? processingTaskOrder.length : tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;

    final themeColor = jobFailed ? AppColors.correctionRed : AppColors.starGold;

    final restartState = useState(false);
    final stoppingState = useState(false);

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

      restartState.value = true;
      try {
        await ref.read(lectureControllerProvider.notifier).startAnalysis(lectureId, force: true);
      } finally {
        if (context.mounted) restartState.value = false;
      }
    }

    // Start Overと違い、止めるだけで新しいジョブは作らない。
    // ジョブ行自体は残る(CANCELLED)ので、後からユーザーが自分のタイミングで
    // Start Analysisを押し直せる。
    Future<void> stopAnalysis() async {
      final confirm = await showCustomDialog(
        context: context,
        title: l10n.processingViewStopDialogTitle,
        message: l10n.processingViewStopDialogMessage,
        confirmLabel: l10n.processingViewStopConfirmButton,
        icon: Icons.stop_circle_outlined,
        isDestructive: true,
      );
      if (confirm != true) return;

      stoppingState.value = true;
      try {
        await ref.read(jobRepositoryProvider).cancelJobsForLecture(lectureId: lectureId);
        DevLog.add('🛑 [ProcessingView] cancel-jobs call succeeded (analysis stop): $lectureId');
      } catch (e) {
        DevLog.add('⚠️ [ProcessingView] cancel-jobs call failed (analysis stop): $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.processingViewStopFailedSnackbar(e.toString()))),
          );
        }
      } finally {
        if (context.mounted) stoppingState.value = false;
      }
    }

    // ★ この Widget はもはや専用の全画面ルートではなく、LectureOverlayCard が
    // FullScreenRevealBlur の中央に置くコンパクトなカードの中身として使われる
    // (何かが既に1つでも生成済みの場合は、代わりに控えめな PipelineProgressBanner
    // が使われ、このカードは「まだ何も生成されていない」間だけ表示される)。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.universe.voidBackground.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.universe.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                jobFailed ? l10n.processingViewFailedTitle : l10n.processingViewAnalyzingTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.processingViewStepsCompletedLabel(completed, total),
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
                    l10n.processingViewHoldToRestartHint,
                    style: TextStyle(
                      color: AppColors.universe.textComet.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton.icon(
                    onPressed: stoppingState.value ? null : stopAnalysis,
                    icon: stoppingState.value
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop_circle_outlined, size: 16),
                    label: Text(
                      stoppingState.value
                          ? l10n.processingViewStoppingLabel
                          : l10n.processingViewStopButton,
                    ),
                    style: TextButton.styleFrom(foregroundColor: AppColors.universe.textComet),
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
                    label: Text(
                      restartState.value
                          ? l10n.processingViewStartingOverLabel
                          : l10n.processingViewStartOverFromScratchButton,
                    ),
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
