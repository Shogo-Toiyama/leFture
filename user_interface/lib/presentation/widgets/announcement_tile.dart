import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/domain/entities/datetime_parameters_formatter.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcement_type_icon.dart';
import 'package:lefture/presentation/widgets/transcript_modal.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';
import 'package:lefture/presentation/widgets/tile_actions_sheet.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

class AnnouncementTile extends HookConsumerWidget {
  const AnnouncementTile({
    super.key,
    required this.announcement,
    this.courseName,
    this.onTap,
    this.showTimestamp = true,
    this.onToggleComplete,
    this.onEdit,
    this.onDelete,
  });

  final Announcement announcement;
  final String? courseName;

  /// タップで詳細へ遷移するコールバック。完了状態では無視される。
  final VoidCallback? onTap;
  final bool showTimestamp;

  /// スライドジェスチャーで完了/未完了を切り替えるコールバック。
  final Future<void> Function(Announcement)? onToggleComplete;

  /// 長押しメニューから編集・削除を行うコールバック。
  final VoidCallback? onEdit;
  final Future<void> Function(Announcement)? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isCompleted = announcement.isCompleted;
    final hasTranscript = announcement.startSid != null && announcement.endSid != null;

    // 講義情報を購読して courseId を取得する
    final lectureAsync = ref.watch(lectureProvider(announcement.lectureId ?? ''));
    final lecture = lectureAsync.asData?.value;
    final courseId = lecture?.courseId;

    final screenWidth = MediaQuery.of(context).size.width;

    // 長押しなどの完了時にスライドするアニメーション用のフック
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );

    final slideOffset = useAnimation(
      Tween<double>(begin: 0.0, end: -screenWidth).animate(
        CurvedAnimation(
          parent: animationController,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
    );

    // タップ時の「スワイプで完了できるよ」というチラ見せ（Peek）アニメーション用
    final peekController = useAnimationController(
      duration: const Duration(milliseconds: 450),
    );

    final peekOffset = useAnimation(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: -75.0).chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -75.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 65,
        ),
      ]).animate(peekController),
    );

    final dragOffset = useState<double>(0.0);

    final currentOffset = (slideOffset != 0.0
            ? slideOffset
            : (peekController.isAnimating ? peekOffset : 0.0)) +
        dragOffset.value;

    final prevCompletedRef = useRef<bool>(isCompleted);
    final prevCompleted = prevCompletedRef.value;
    prevCompletedRef.value = isCompleted;

    final hasSwiped = useRef<bool>(false);

    useEffect(() {
      if (isCompleted && prevCompleted == false) {
        if (hasSwiped.value) {
          hasSwiped.value = false;
        } else {
          Future.microtask(() async {
            if (!context.mounted || animationController.isAnimating) return;
            await animationController.forward();
            if (context.mounted) {
              await animationController.reverse();
            }
          });
        }
      }
      return null;
    }, [isCompleted]);

    final tileContent = Stack(
      children: [
        if (currentOffset != 0.0)
          Positioned.fill(
            child: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: isCompleted ? Colors.blueGrey.shade700 : Colors.green.shade700,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCompleted ? Icons.undo : Icons.check,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCompleted ? 'Undo' : 'Done',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Transform.translate(
          offset: Offset(currentOffset, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.universe.voidBackground, // 透過防止用のソリッド背景色
                borderRadius: BorderRadius.circular(14),
              ),
            child: Opacity(
              opacity: isCompleted ? 0.55 : 1.0,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.universe.glassWhiteLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.universe.glassBorder.withValues(alpha: 0.4)
                        : AppColors.universe.glassBorder,
                  ),
                ),
                child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle
                      : iconForAnnouncementType(announcement.type),
                  color: isCompleted
                      ? colorForAnnouncementType(announcement.type).withValues(alpha: 0.6)
                      : colorForAnnouncementType(announcement.type),
                  size: 20,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  // 右上の「View Transcript」ボタンと重ならないように右側に余白を持たせる
                  padding: EdgeInsets.only(right: hasTranscript && !isCompleted ? 90 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title?.trim().isNotEmpty == true
                            ? announcement.title!.trim()
                            : 'Announcement',
                        style: TextStyle(
                          color: isCompleted
                              ? AppColors.universe.textComet
                              : AppColors.universe.textStarlight,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.universe.textComet,
                        ),
                      ),
                      if (announcement.description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          announcement.description!.trim(),
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 13,
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.universe.textComet,
                          ),
                        ),
                      ],
                      if (showTimestamp) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (courseName != null) courseName!,
                            formatDatetimeParameters(
                                  announcement.datetimeParameters,
                                  anchor: announcement.createdAt,
                                  locale: l10n.localeName,
                                ) ??
                                DateFormat.yMMMd(l10n.localeName).add_jm().format(announcement.createdAt.toLocal()),
                          ].join(' · '),
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (isCompleted) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Done • Swipe to undo',
                          style: TextStyle(
                            color: Colors.green.shade400.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 未完了かつ onTap があるときのみ矢印を表示
              if (onTap != null && !isCompleted) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.universe.textComet,
                  size: 18,
                ),
              ],
            ],
          ),
          // 右上に「View Transcript」ボタンを配置
          if (hasTranscript && !isCompleted)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  if (announcement.lectureId != null) {
                    showTranscriptModal(
                      context,
                      lectureId: announcement.lectureId!,
                      startSid: announcement.startSid,
                      endSid: announcement.endSid,
                      courseId: courseId,
                    );
                  }
                },
                // 💡 ポイント1: 透明な余白部分をタップしても反応するようにする
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // 💡 ポイント2: ここで上下に「透明な追加のタップ領域」を作る
                  // 元のボタンの高さが約20なので、上下に12ずつ足すと 20 + 24 = 44 になります。
                  padding: const EdgeInsets.only(top: 24),
                  child: Container(
                    // 以下の Container の中身は一切いじらなくてOK（見た目はそのまま！）
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.deepGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.deepGold.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 10,
                          color: AppColors.starGold,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Source',
                          style: TextStyle(
                            color: AppColors.starGold,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
),
),
),
      ],
    );

    Widget tile = tileContent;

    // 長押しでアクションシートを表示（onEdit または onDelete が設定されている場合のみ）
    if (onEdit != null || onDelete != null) {
      final titleText = announcement.title?.trim().isNotEmpty == true
          ? announcement.title!.trim()
          : 'Announcement';
      tile = GestureDetector(
        onLongPress: () => showTileActionsSheet(
          context: context,
          title: titleText,
          onToggleComplete: onToggleComplete != null
              ? () => onToggleComplete!(announcement)
              : null,
          toggleCompleteLabel: isCompleted ? 'Mark as Todo' : 'Mark as Done',
          toggleCompleteIcon: isCompleted
              ? Icons.undo
              : Icons.check_circle_outline,
          onEdit: () {
            if (onEdit != null) onEdit!();
          },
          onDelete: () async {
            final confirm = await showCustomDialog(
              context: context,
              title: l10n.announcementDeleteDialogTitle,
              message: l10n.announcementDeleteDialogMessage(titleText),
              confirmLabel: l10n.commonDeleteButton,
              icon: Icons.delete_outline,
              isDestructive: true,
            );
            if (confirm == true && onDelete != null) {
              await onDelete!(announcement);
            }
          },
        ),
        child: tile,
      );
    }

    // 未完了かつ onTap があるときのみタップ遷移を有効化
    // onTap がない場合（LectureViewerPage / AnnouncementsSheet 等）はタップ時にスワイプのチラ見せ（Peek）アニメーションを実行
    tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (onTap != null && !isCompleted) {
          onTap!();
        } else if (onToggleComplete != null) {
          if (!peekController.isAnimating && !animationController.isAnimating) {
            peekController.forward(from: 0.0);
          }
        }
      },
      child: tile,
    );

    // スワイプDone/Undo機能 (自前ドラッグで角丸を完璧に保持)
    if (onToggleComplete != null) {
      tile = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          // 端（画面全幅）まで最後までスライド可能にする
          final newOffset = (dragOffset.value + details.delta.dx).clamp(-screenWidth, 0.0);
          dragOffset.value = newOffset;
        },
        onHorizontalDragEnd: (details) async {
          final currentDrag = dragOffset.value;
          final threshold = -screenWidth * 0.35;

          // フリック速度は無視し、しっかり画面幅の35%以上引っ張った場合のみ Done にする
          if (currentDrag <= threshold) {
            hasSwiped.value = true;

            // ① 現在地から画面外 (-screenWidth) まで滑らかに最後までスライドし切る
            const durationMs = 200;
            final start = dragOffset.value;
            final distance = -screenWidth - start;
            final startTime = DateTime.now().millisecondsSinceEpoch;

            while (true) {
              final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
              if (elapsed >= durationMs) {
                dragOffset.value = -screenWidth;
                break;
              }
              final t = elapsed / durationMs;
              final ease = 1.0 - math.pow(1.0 - t, 3);
              dragOffset.value = start + distance * ease;
              await Future.delayed(const Duration(milliseconds: 16));
            }

            // ② 端までスライドし切ってから Done / Undo 状態を切り替え
            try {
              await onToggleComplete!(announcement);
            } catch (e, stack) {
              hasSwiped.value = false;
              DevLog.add('⚠️ [AnnouncementTile] Toggle complete failed: $e\n$stack');
            }

            // ③ 位置を 0.0 にリセット
            dragOffset.value = 0.0;
          } else {
            // 35% 未満の場合はキャンセルし、元の位置に戻す
            dragOffset.value = 0.0;
          }
        },
        onHorizontalDragCancel: () {
          dragOffset.value = 0.0;
        },
        child: tile,
      );
    }

    return tile;
  }
}
