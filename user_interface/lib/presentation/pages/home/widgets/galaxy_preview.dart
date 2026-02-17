// lib/presentation/pages/home/widgets/galaxy_preview.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/galaxy/galaxy_view.dart';

class GalaxyPreview extends StatelessWidget {
  const GalaxyPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push(AppRoutes.learningGalaxy);
      },
      child: Stack(
        children: [
          // 1. 銀河本体
          const Hero(
            tag: 'galaxy',
            child: GalaxyView(),
          ),

          // 2. 上のグラデーション (上から下へ 黒 -> 透明)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 30, // グラデーションの幅
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.universe.voidBackground,
                    AppColors.universe.voidBackground.withValues(alpha: 0.3),
                    AppColors.universe.voidBackground.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // 3. 下のグラデーション (下から上へ 黒 -> 透明)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 30,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.universe.voidBackground,
                    AppColors.universe.voidBackground.withValues(alpha: 0.3),
                    AppColors.universe.voidBackground.withValues(alpha: 0.0), 
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}