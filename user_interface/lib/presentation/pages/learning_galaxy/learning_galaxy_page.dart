import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/widgets/galaxy/galaxy_view.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class LearningGalaxyPage extends StatelessWidget {
  const LearningGalaxyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Center(
        child: Hero(
          tag: 'galaxy',
          child: GalaxyView(),
        ),
      ),
    );
  }
}