import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';

/// パイプラインの各ステップ(processingTaskOrder順)を1行ずつ表示するリスト。
/// [ProcessingView]（分析中）と[LectureStatusScaffold]のfailed状態、両方から
/// 共有される。[jobFailed]は「ジョブ全体が既にFAILEDと確定しているか」を表し、
/// これがtrueの間はFAILEDなタスクを5分待たず即リトライ可能として扱う
/// （バックエンドが既に自動リトライを使い切ったと判定済みのため）。
class PipelineStepsList extends StatelessWidget {
  const PipelineStepsList({super.key, required this.tasks, required this.jobFailed});

  final List<ProcessingTask> tasks;
  final bool jobFailed;

  @override
  Widget build(BuildContext context) {
    final byType = {for (final t in tasks) t.taskType: t};

    // TRANSCRIBE_MASTERとCHECK_AND_ASSEMBLEは互いに排他的で、バックエンドは
    // ジョブ作成時にどちらか一方のタスク行しかINSERTしない(realtime収録か
    // どうかで選択)。tasksが空の間(取得直後の一瞬)はどちらか判別できないため
    // 両方見せておき、実際のタスク一覧が届いたら「存在しない方」を除外する。
    // これ以外のタスク種別は常に全ジョブでINSERTされるため対象外。
    final visibleTaskOrder = tasks.isEmpty
        ? processingTaskOrder
        : processingTaskOrder.where((type) {
            if (type == 'TRANSCRIBE_MASTER' || type == 'CHECK_AND_ASSEMBLE') {
              return byType.containsKey(type);
            }
            return true;
          }).toList();

    // 順番的に「最初の未完了ステップ」を実行中として扱う
    String? currentType;
    for (final type in visibleTaskOrder) {
      final t = byType[type];
      if (t == null || (!t.isCompleted && !t.isCancelled)) {
        currentType = type;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in visibleTaskOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StepRow(
              taskType: type,
              task: byType[type],
              isCurrent: type == currentType,
              jobFailed: jobFailed,
            ),
          ),
      ],
    );
  }
}

class _StepRow extends HookConsumerWidget {
  const _StepRow({
    required this.taskType,
    required this.task,
    required this.isCurrent,
    required this.jobFailed,
  });

  final String taskType;
  final ProcessingTask? task;
  final bool isCurrent;
  final bool jobFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = localizedProcessingTaskLabel(l10n, taskType);

    if (task == null) {
      // タスク行自体はバックエンドがジョブ作成時に一括INSERTするため、
      // 「現在の番のはずなのにtaskがまだ無い」のはjobStreamProviderと
      // jobTasksStreamProviderの取得タイミングがずれているだけ(実行中は確定)。
      // ここでも「未着手」表示にしてしまうと、RUNNING中なのにスピナーが
      // 出ない瞬間ができてしまうため、isCurrentならスピナー表示を優先する。
      if (isCurrent) {
        return _StepTile(
          icon: null,
          iconColor: AppColors.starGold,
          label: label,
          showSpinner: true,
          subtitle: Text(l10n.pipelineStepsInProgressLabel),
        );
      }
      return _StepTile(
        icon: Icons.circle_outlined,
        iconColor: AppColors.universe.textComet.withValues(alpha: 0.4),
        label: label,
        labelColor: AppColors.universe.textComet.withValues(alpha: 0.6),
        subtitle: null,
      );
    }

    if (task!.isCancelled) {
      return _StepTile(
        icon: Icons.block,
        iconColor: AppColors.universe.textComet.withValues(alpha: 0.4),
        label: label,
        labelColor: AppColors.universe.textComet.withValues(alpha: 0.6),
        strikethrough: true,
        subtitle: Text(l10n.pipelineStepsCancelledLabel),
      );
    }

    if (task!.isCompleted) {
      return _RetryableCompletedStep(taskType: taskType, task: task!, label: label);
    }

    // タスクが「本当に詰まっている」かどうか:
    // ジョブが既にFAILED確定済みなら5分待たず即座に、そうでなければ
    // isStaleFailed(5分ヒューリスティック)で判定する
    final isStuck = task!.isFailed && (jobFailed || task!.isStaleFailed);
    if (isStuck) {
      return _StuckStepCard(taskType: taskType, task: task!, label: label);
    }

    // FAILEDだがまだジョブは確定していない = Cloud Tasksが裏で自動リトライ中の可能性
    if (task!.isFailed) {
      return _StepTile(
        icon: Icons.autorenew,
        iconColor: AppColors.alertAmber,
        label: label,
        subtitle: Text(
          l10n.pipelineStepsRetryingAutomaticallyLabel,
          style: TextStyle(color: AppColors.alertAmber.withValues(alpha: 0.9), fontSize: 12),
        ),
      );
    }

    if (isCurrent) {
      return _StepTile(
        icon: null,
        iconColor: AppColors.starGold,
        label: label,
        showSpinner: true,
        subtitle: Text(l10n.pipelineStepsInProgressLabel),
      );
    }

    // ここに来るのは基本PENDING(まだ順番が来ていない)
    return _StepTile(
      icon: Icons.circle_outlined,
      iconColor: AppColors.universe.textComet.withValues(alpha: 0.4),
      label: label,
      labelColor: AppColors.universe.textComet.withValues(alpha: 0.6),
      subtitle: null,
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
    this.showSpinner = false,
    this.strikethrough = false,
    this.trailing,
  });

  final IconData? icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final Widget? subtitle;
  final bool showSpinner;
  final bool strikethrough;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: showSpinner
              ? CircularProgressIndicator(strokeWidth: 2, color: iconColor)
              : Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: labelColor ?? AppColors.universe.textStarlight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: strikethrough ? TextDecoration.lineThrough : null,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle(
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _RetryableCompletedStep extends HookConsumerWidget {
  const _RetryableCompletedStep({required this.taskType, required this.task, required this.label});

  final String taskType;
  final ProcessingTask task;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isRetrying = useState(false);

    Future<void> retryFromHere() async {
      final downstream = downstreamOf(taskType)..remove(taskType);
      final downstreamLabels = processingTaskOrder
          .where(downstream.contains)
          .map((t) => localizedProcessingTaskLabel(l10n, t))
          .toList();

      final message = downstreamLabels.isEmpty
          ? l10n.pipelineStepsRetryConfirmMessageSimple(label)
          : l10n.pipelineStepsRetryConfirmMessageWithDownstream(
              label,
              downstreamLabels.join(', '),
            );

      final confirm = await showCustomDialog(
        context: context,
        title: l10n.pipelineStepsRetryDialogTitle,
        message: message,
        confirmLabel: l10n.pipelineStepsRetryConfirmButton,
        icon: Icons.refresh,
        isDestructive: true,
      );
      if (confirm != true) return;

      isRetrying.value = true;
      try {
        await ref.read(jobRepositoryProvider).retryTask(taskId: task.id);
        // watchTasksForJobは全タスクが終端状態(FAILED/CANCELLED込み)になると
        // ポーリングを永久停止する。リトライはジョブを作り直さず同じジョブ内で
        // タスクをRUNNING/QUEUEDに戻すだけなので、invalidateして明示的に
        // ポーリングを再起動しないと、以後永久に古いスナップショットのまま
        // 更新されなくなる(スピナーが二度と出ない不具合の原因)。
        ref.invalidate(jobTasksStreamProvider(task.jobId));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.pipelineStepsRetryFailedSnackbar(e.toString()))),
          );
        }
      } finally {
        if (context.mounted) isRetrying.value = false;
      }
    }

    return _StepTile(
      icon: Icons.check_circle,
      iconColor: AppColors.growthGreen,
      label: label,
      subtitle: Text(DateFormat.jm(l10n.localeName).format(task.updatedAt.toLocal())),
      trailing: IconButton(
        onPressed: isRetrying.value ? null : retryFromHere,
        tooltip: l10n.pipelineStepsRetryTooltip,
        icon: isRetrying.value
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.universe.textComet),
              )
            : Icon(Icons.replay, size: 18, color: AppColors.universe.textComet),
      ),
    );
  }
}

class _StuckStepCard extends HookConsumerWidget {
  const _StuckStepCard({required this.taskType, required this.task, required this.label});

  final String taskType;
  final ProcessingTask task;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isRetrying = useState(false);
    final error = useState<String?>(null);

    Future<void> retry() async {
      isRetrying.value = true;
      error.value = null;
      try {
        await ref.read(jobRepositoryProvider).retryTask(taskId: task.id);
        // 理由は_RetryableCompletedStep.retryFromHereと同じ:
        // watchTasksForJobは全タスク終端状態でポーリングを永久停止するため、
        // 同じジョブ内でのリトライ後は明示的に再起動する必要がある。
        ref.invalidate(jobTasksStreamProvider(task.jobId));
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
                  label,
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
              label: Text(
                isRetrying.value
                    ? l10n.pipelineStepsRetryingLabel
                    : l10n.pipelineStepsRetryThisStepButton,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
