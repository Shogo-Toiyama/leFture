import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/widgets/galaxy/galaxy_view.dart';

class GoalTreePage extends StatelessWidget {
  const GoalTreePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Tree'),
      ),
      body: SizedBox.expand(child: GalaxyView()),
    );
  }
}