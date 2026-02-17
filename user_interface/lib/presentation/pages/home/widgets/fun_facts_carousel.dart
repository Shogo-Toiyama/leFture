import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class FunFactsCarousel extends StatelessWidget {
  const FunFactsCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final carouselHeight = availableHeight - 20;
          return Column(
          mainAxisAlignment: MainAxisAlignment.center, // 縦中央寄せ
          children: [
            SizedBox(
              height: carouselHeight > 0 ? carouselHeight : 0,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.9),
                itemCount: 5,
                itemBuilder: (context, index) => _FunFactCard(index: index),
              ),
            ),
            const SizedBox(height: 8),
            // インジケーター (.....)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == 0 ? AppColors.starGold : AppColors.universe.textComet.withValues(alpha: 0.3),
                ),
              )),
            ),
          ],
        );
      }
    );
  }
}

class _FunFactCard extends StatelessWidget {
  final int index;
  const _FunFactCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ()=>{ context.push(AppRoutes.notesRoot) },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Column(
          children: [
            // 上部: Fact内容 (3/4)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Text(
                    'Did you know? Quantum entanglement allows particles to affect each other instantly over any distance.\nDid you know? Quantum entanglement allows particles to affect each other instantly over any distance.',
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            // 下部: メタデータ (1/4)
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Intro to Physics $index',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite_border, color: Colors.white54, size: 20),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}