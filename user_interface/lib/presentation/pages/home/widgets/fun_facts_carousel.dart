import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class FunFactsCarousel extends StatefulWidget {
  const FunFactsCarousel({super.key});

  @override
  State<FunFactsCarousel> createState() => _FunFactsCarouselState();
}

class _FunFactsCarouselState extends State<FunFactsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const carouselHeight = 160.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: carouselHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: 5,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) => _FunFactCard(index: index),
          ),
        ),
        const SizedBox(height: 8),
        // インジケーター (.....)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == _currentPage
                    ? AppColors.starGold
                    : AppColors.universe.textComet.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FunFactsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;

  FunFactsHeaderDelegate({this.height = 190.0});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // スクロール時に背景が少し暗く浮かび上がる演出（グラスモーフィズム調）
    final isPinned = shrinkOffset > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isPinned 
            ? AppColors.universe.voidBackground.withValues(alpha: 0.8)
            : Colors.transparent,
      ),
      alignment: Alignment.center,
      height: height,
      child: const FunFactsCarousel(),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant FunFactsHeaderDelegate oldDelegate) {
    return oldDelegate.height != height;
  }
}

class _FunFactCard extends StatelessWidget {
  final int index;
  const _FunFactCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.notesRoot),
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
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    'Did you know? Quantum entanglement allows particles to affect each other instantly over any distance.',
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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