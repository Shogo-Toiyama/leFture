import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class LectureTile extends StatelessWidget {
  const LectureTile({
    super.key,
    required this.lecture,
    required this.onTap,
  });

  final Lecture lecture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(lecture.lectureDatetime);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        // ガラスの背景
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // アイコン部分
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    // 少し明るいガラス
                    color: AppColors.universe.glassWhiteHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppColors.starGold, // アイコンはゴールド
                  ),
                ),
                const SizedBox(width: 16),
                
                // テキスト情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lecture.title ?? 'Untitled Lecture',
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 右端の矢印
                Icon(
                  Icons.chevron_right,
                  color: AppColors.universe.textComet.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}