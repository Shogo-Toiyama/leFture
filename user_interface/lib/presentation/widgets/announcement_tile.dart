import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/domain/entities/datetime_parameters_formatter.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_transcript_modal.dart';

class AnnouncementTile extends ConsumerWidget {
  const AnnouncementTile({
    super.key,
    required this.announcement,
    this.courseName,
    this.onTap,
    this.showTimestamp = true,
    this.onToggleComplete,
  });

  final Announcement announcement;
  final String? courseName;

  /// タップで詳細へ遷移するコールバック。完了状態では無視される。
  final VoidCallback? onTap;
  final bool showTimestamp;

  /// スライドジェスチャーで完了/未完了を切り替えるコールバック。
  final Future<void> Function(Announcement)? onToggleComplete;

  static final _dateFmt = DateFormat('MMM d, yyyy · h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompleted = announcement.isCompleted;
    final hasTranscript = announcement.startSid != null && announcement.endSid != null;

    // 講義情報を購読して courseId を取得する
    final lectureAsync = ref.watch(lectureProvider(announcement.lectureId ?? ''));
    final lecture = lectureAsync.asData?.value;
    final courseId = lecture?.courseId;

    final tileContent = Container(
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
                    ? Icons.check_circle_outline
                    : iconForAnnouncementType(announcement.type),
                color: isCompleted ? Colors.green.shade400 : AppColors.starGold,
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
                                ) ??
                                _dateFmt.format(announcement.createdAt.toLocal()),
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
                    showAnnouncementTranscriptModal(
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
    );

    Widget tile = tileContent;

    // 未完了かつ onTap があるときのみタップ遷移を有効化
    if (onTap != null && !isCompleted) {
      tile = GestureDetector(
        onTap: onTap,
        child: tile,
      );
    }

    // スワイプDone/Undo機能
    if (onToggleComplete != null) {
      tile = Dismissible(
        key: ValueKey('announcement_${announcement.id}_$isCompleted'),
        direction: DismissDirection.endToStart,
        // confirmDismiss で false を返すことで物理的には消さず、コールバックのみ実行
        confirmDismiss: (_) async {
          await onToggleComplete!(announcement);
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.blueGrey.shade700
                : Colors.green.shade700,
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
        child: tile,
      );
    }

    return tile;
  }
}
