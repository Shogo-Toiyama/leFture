import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';
import 'fun_facts_carousel.dart';

class CoursesHeaderWidget extends StatelessWidget {
  const CoursesHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Courses >
        InkWell(
          onTap: () => context.push(AppRoutes.coursesRootPath),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.homeCoursesSectionTitle,
                  style: TextStyle(
                    color: AppColors.starGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.starGold,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        // Recent Lectures
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Text(
            l10n.homeRecentLecturesSectionTitle,
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class CombinedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double funFactsHeight;
  final double coursesHeaderHeight;
  final double scrollOffset;

  CombinedHeaderDelegate({
    this.funFactsHeight = 190.0,
    this.coursesHeaderHeight = 84.0,
    required this.scrollOffset,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // 銀河の高さ分（260px）のスクロールで透明度が 0.0 から 0.95 まで変化する
    const double galaxyHeight = 260.0;
    final progress = (scrollOffset / galaxyHeight).clamp(0.0, 1.0);
    final opacity = progress * 0.95;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.voidBackground.withValues(alpha: opacity),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: funFactsHeight,
            child: const FunFactsCarousel(),
          ),
          SizedBox(
            height: coursesHeaderHeight,
            child: const CoursesHeaderWidget(),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => funFactsHeight + coursesHeaderHeight;

  @override
  double get minExtent => funFactsHeight + coursesHeaderHeight;

  @override
  bool shouldRebuild(covariant CombinedHeaderDelegate oldDelegate) {
    return oldDelegate.funFactsHeight != funFactsHeight ||
           oldDelegate.coursesHeaderHeight != coursesHeaderHeight ||
           oldDelegate.scrollOffset != scrollOffset;
  }
}
