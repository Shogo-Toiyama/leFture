import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';

class NotStartedView extends ConsumerWidget {
  const NotStartedView({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(lectureControllerProvider);
    final isLoading = controllerState.isLoading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome, 
              size: 80, 
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 32),
            Text(
              'Ready to Analyze',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'The audio is ready. Generate transcript, summary, and notes with AI.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant
              ),
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: isLoading ? null : () {
                ref.read(lectureControllerProvider.notifier).startAnalysis(lectureId);
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              icon: isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                  : const Icon(Icons.play_arrow),
              label: Text(isLoading ? 'Starting...' : 'Start Analysis'),
            ),
            if (controllerState.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Error: ${controllerState.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}