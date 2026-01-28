import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart';

class ProcessingView extends ConsumerWidget {
  const ProcessingView({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(lectureId));
    final job = jobAsync.value;

    const totalSteps = 7;
    final step = job?.stepNumber ?? 0;
    final currentStepNum = step < 1 ? 0 : step;
    final currentStepName = job?.currentStep ?? 'Initializing...';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48, 
            height: 48, 
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 32),
          Text(
            'Analyzing Lecture...',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Step $currentStepNum / $totalSteps',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            currentStepName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}