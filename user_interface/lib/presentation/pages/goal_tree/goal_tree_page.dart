import 'package:flutter/material.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';

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