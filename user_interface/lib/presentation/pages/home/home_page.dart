import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

import 'widgets/home_app_bar.dart';
import 'widgets/announcement_bar.dart';
import 'widgets/galaxy_preview.dart';
import 'widgets/fun_facts_carousel.dart';
import 'widgets/recent_lectures_list.dart';
import 'widgets/bottom_control_bar.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: Column(
          children: [
            const HomeAppBar(),
            
            Expanded(
              child: Column(
                children: [
                  const AnnouncementBar(),

                  const Expanded(
                    flex: 5, 
                    child: GalaxyPreview(),
                  ),
                  const Expanded(
                    flex: 4,
                    child: FunFactsCarousel(),
                  ),
                  const Expanded(
                    flex: 6,
                    child: RecentLecturesList(),
                  ),
                ],
              ),
            ),
            const BottomControlBar(),
          ],
        ),
      ),
    );
  }
}