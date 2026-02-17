import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class AnnouncementBar extends StatelessWidget {
  const AnnouncementBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // グラスモーフィズム
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        children: [
          // アイコン
          const Icon(Icons.star, color: AppColors.starGold, size: 20),
          const SizedBox(width: 12),
          // テキスト
          Expanded(
            child: Text(
              'Keep exploring the universe!', // Fake Message
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 矢印
          Icon(Icons.arrow_forward_ios, 
            color: AppColors.universe.textComet, size: 12),
        ],
      ),
    );
  }
}