import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class RecentLecturesList extends StatelessWidget {
  const RecentLecturesList({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _LectureCard(index: index),
          );
        },
        childCount: 10, // カード10枚
      ),
    );
  }
}

class _LectureCard extends StatelessWidget {
  final int index;
  const _LectureCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.universe.glassWhiteHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined, color: AppColors.starGold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Introduction to Computer Science - Week $index',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: AppColors.universe.textComet),
                    const SizedBox(width: 4),
                    Text(
                      '2 hours ago',
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_outline, color: Colors.white30, size: 28),
        ],
      ),
    );
  }
}