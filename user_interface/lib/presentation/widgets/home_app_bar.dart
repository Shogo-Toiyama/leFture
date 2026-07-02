import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'recording_timer_chip.dart';

class HomeAppBar extends StatelessWidget {
  const HomeAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左: 録音チップ (リアルタイムで同期)
          const RecordingTimerChip(),

          // 右: プロフィール & クレジット残量
          GestureDetector(
            onTap: () => context.push(AppRoutes.profile),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // クレジット残量ゲージ
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: 0.7, // Fake: 残り70%
                    strokeWidth: 3,
                    backgroundColor: AppColors.universe.glassWhiteLow,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.starGold),
                  ),
                ),
                // アイコン本体
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white, // 画像がない時の背景
                  ),
                  child: const Icon(Icons.person, color: Colors.grey, size: 20),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
