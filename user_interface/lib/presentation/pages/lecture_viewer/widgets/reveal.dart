// lib/presentation/pages/lecture_viewer/widgets/reveal.dart
//
// LectureViewerPageの「要素ごとに完成したものから出していく」演出を支える
// 共通部品。各コンテンツブロック(タイトル/要約・Review Cards・Fun Fact等)を
// 生成するタスクの状態から、そのブロックが今どう見えるべきかを判定する。

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 1つのコンテンツブロックの表示状態。
enum RevealState {
  /// まだ生成されていない(タスクが未完了)。シマー付きスケルトンを見せる。
  locked,

  /// 生成が完了した。実データを見せる。
  ready,

  /// 生成タスクがFAILEDのまま復帰見込みが無い。小さいエラー+リトライを見せる。
  blocked,
}

class ElementReveal {
  const ElementReveal(this.state, [this.task]);

  final RevealState state;

  /// state==blockedの時のみ非null。リトライ呼び出しに使う。
  final ProcessingTask? task;

  bool get isReady => state == RevealState.ready;
  bool get isBlocked => state == RevealState.blocked;
}

/// [startType]から[processingTaskDependencies]を遡り、実際にFAILEDになっている
/// 直近の祖先タスクを探す。
///
/// 上流タスク(例: IMAGE_RENDERING)が力尽きると、それに依存する下流タスク
/// (例: FINALIZE_JOB)は一度もQUEUEDにすらならずPENDINGのまま取り残される。
/// バックエンドの/retry-taskはFAILED/COMPLETEDの行しか受け付けないため、
/// PENDINGのままの下流タスクIDをそのまま渡すと400になる —— 実際に落ちた
/// 祖先を見つけて、そちらをリトライ対象として案内する必要がある。
ProcessingTask? _findFailedBlocker(
  String startType,
  Map<String, ProcessingTask> tasksByType,
) {
  final visited = <String>{};
  final queue = <String>[startType];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!visited.add(current)) continue;
    final t = tasksByType[current];
    if (t != null && t.isFailed) return t;
    queue.addAll(processingTaskDependencies[current] ?? const []);
  }
  return null;
}

/// [taskTypes]のうち最初に見つかったタスクの状態から、そのブロックの
/// [ElementReveal]を判定する。
///
/// ★ readyの判定は「タスクが完了したか」だけを見る(ローカルDBにデータが
/// 実際に届いているかは見ない)。理由: Announcements/Fun Factのように
/// 「生成した結果0件」が正常な完了状態であるブロックがあるため、データの
/// 有無で判定すると"正常に空"なブロックが永久にロック状態のまま止まって
/// しまう。データの反映はタスク完了直後の差分Pull(pipeline_reveal_sync.dart)
/// が数百ms〜1秒程度で追いつく前提。
///
/// [jobFailed]はジョブ全体が既にFAILED/ERROR確定済みかどうか。これがtrueの
/// 間はFAILEDなタスクを[ProcessingTask.staleFailedThreshold]待たず即座に
/// blocked扱いにする(バックエンドが既に自動リトライを使い切ったと判定済みのため)。
/// PipelineStepsListの_StepRowと同じ判定ルールを共有している。
ElementReveal computeReveal({
  required List<String> taskTypes,
  required Map<String, ProcessingTask> tasksByType,
  required bool jobFailed,
}) {
  ProcessingTask? matched;
  for (final type in taskTypes) {
    final t = tasksByType[type];
    if (t != null) {
      matched = t;
      break;
    }
  }

  if (matched == null) return const ElementReveal(RevealState.locked);
  if (matched.isCompleted) return const ElementReveal(RevealState.ready);

  if (matched.isFailed && (jobFailed || matched.isStaleFailed)) {
    return ElementReveal(RevealState.blocked, matched);
  }

  // このタスク自身はまだFAILEDになっていない(PENDING/QUEUED/RUNNINGのまま)が、
  // ジョブ全体は既にFAILED/ERROR確定済み = 上流のどこかが力尽きて、このタスクは
  // 永久に取り残されている。実際に落ちた祖先タスクを遡って探し、それを
  // リトライ対象として案内する。
  if (jobFailed) {
    final blocker = _findFailedBlocker(matched.taskType, tasksByType);
    if (blocker != null) {
      return ElementReveal(RevealState.blocked, blocker);
    }
  }

  // CANCELLED(Start Overで打ち切られた等)やPENDING/QUEUED/RUNNINGはlocked。
  // CANCELLEDは通常、直後に新しいジョブのタスクへ置き換わるため一時的な表示。
  return const ElementReveal(RevealState.locked);
}

/// シマー(光が流れるアニメーション)付きのプレースホルダー矩形。
/// 依存パッケージを増やしたくないため、AnimationController+ShaderMaskの
/// 自前実装にしている。
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 12,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.universe.glassWhiteLow;
    final highlight = AppColors.universe.glassBorder;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            // -1.5〜1.5の範囲でグラデーションの帯を横に流す
            final t = _controller.value * 3 - 1.5;
            return LinearGradient(
              begin: Alignment(-1.0 + t, 0),
              end: Alignment(0.0 + t, 0),
              colors: [base, highlight, base],
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// [reveal]の状態に応じて、ロック中(シマー)/完成(実データ)/詰まった(再試行)を
/// フェード切り替えする共通ラッパー。
class RevealSwitcher extends StatelessWidget {
  const RevealSwitcher({
    super.key,
    required this.reveal,
    required this.locked,
    required this.ready,
    this.blockedLabel,
  });

  final ElementReveal reveal;
  final Widget locked;
  final Widget ready;

  /// blocked時に見せる短いラベル(「Review Cardsの生成」など)。
  /// nullの場合はタスク種別からローカライズ済みラベルを自動生成する。
  final String? blockedLabel;

  @override
  Widget build(BuildContext context) {
    final child = switch (reveal.state) {
      RevealState.ready => KeyedSubtree(key: const ValueKey('ready'), child: ready),
      RevealState.blocked => KeyedSubtree(
          key: const ValueKey('blocked'),
          child: _BlockedBlock(task: reveal.task!, label: blockedLabel),
        ),
      RevealState.locked => KeyedSubtree(key: const ValueKey('locked'), child: locked),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween(begin: 0.98, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: child,
    );
  }
}

/// 生成タスクが詰まった状態の、要素インライン用コンパクトカード。
/// 全画面版の詳細(PipelineStepsListの_StuckStepCard)と違い、ここは
/// 1ブロック分のスペースに収まる簡潔な表示にする。
class _BlockedBlock extends HookConsumerWidget {
  const _BlockedBlock({required this.task, this.label});

  final ProcessingTask task;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isRetrying = useState(false);

    Future<void> retry() async {
      isRetrying.value = true;
      try {
        await ref.read(jobRepositoryProvider).retryTask(taskId: task.id);
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.correctionRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.correctionRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label ?? localizedProcessingTaskLabel(l10n, task.taskType),
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          isRetrying.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.correctionRed),
                )
              : IconButton(
                  onPressed: retry,
                  tooltip: l10n.pipelineStepsRetryTooltip,
                  icon: const Icon(Icons.refresh, size: 18, color: AppColors.correctionRed),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
        ],
      ),
    );
  }
}

/// NotStarted/Processing/Failedのいずれかで、まだ何も生成物が届いていない間
/// (=[hasAnyReady]がfalse)に画面全体へかけるグラデーションブラー。
///
/// 下層シャープ層は上端境界付近でのみ表示し、境界線の少し下で完全透明(0%)に消滅させます。
/// 代わりに100%ブラー([ImageFiltered])のかかった層が境界線下で100%不透明になるようクロスフェードさせ、
/// 画面下部が100%しっかりとブラー化される(シャープな下地が透けない)ように実装しています。
class FullScreenRevealBlur extends StatelessWidget {
  const FullScreenRevealBlur({
    super.key,
    required this.active,
    required this.child,
    required this.overlay,
  });

  final bool active;
  final Widget child;
  final Widget overlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. シャープ層 (activeがfalseの時は全画面表示。activeがtrueの時は上端境界付近でのみフェード表示し、下部で完全消滅)
        IgnorePointer(
          ignoring: active,
          child: active
              ? ShaderMask(
                  key: const ValueKey('sharp-fade'),
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,               // 上端(境界直下): 100% シャープ
                        Color.fromRGBO(0, 0, 0, 0.5), // 境界線付近: 50% シャープ
                        Colors.transparent,         // 境界線のすぐ下: 0% (完全消滅!)
                      ],
                      stops: [0.0, 0.015, 0.04],
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: child,
                )
              : KeyedSubtree(key: const ValueKey('sharp-full'), child: child),
        ),

        // 2. ブラー層 (activeの時のみ表示。境界直下0% -> 境界線付近50% -> 境界線下で100%実体化)
        if (active)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: ShaderMask(
                key: const ValueKey('blurred-fade'),
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,           // 上端(境界直下): 0% ブラー
                      Color.fromRGBO(0, 0, 0, 0.5), // 境界線付近: 50% ブラー
                      Colors.black,                 // 境界線のすぐ下: 100% ブラー (下部はこれのみ!)
                    ],
                    stops: [0.0, 0.015, 0.04],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: child,
                ),
              ),
            ),
          ),

        // 3. 暗め背景と中央カード
        if (active)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !active,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: active
                    ? Container(
                        key: const ValueKey('overlay'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              AppColors.universe.voidBackground.withValues(alpha: 0.25),
                              AppColors.universe.voidBackground.withValues(alpha: 0.55),
                            ],
                            stops: const [0.0, 0.02, 0.08],
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: overlay,
                      )
                    : const SizedBox.shrink(key: ValueKey('no-overlay')),
              ),
            ),
          ),
      ],
    );
  }
}
