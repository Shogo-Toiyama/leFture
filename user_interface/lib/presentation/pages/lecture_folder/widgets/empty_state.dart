// lib/presentation/pages/lecture_folder/widgets/empty_state.dart
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              const Icon(Icons.folder_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No folders yet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Create a folder to organize your lecture notes',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Create folder'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
