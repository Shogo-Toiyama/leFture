import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/domain/entities/datetime_parameters_formatter.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';

class AnnouncementTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isCompleted = announcement.isCompleted;
    final tileContent = Opacity(
      opacity: 1.0,
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
        child: Row(
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
