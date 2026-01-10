import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Dashboard Page',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Dashboard coming soon...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}