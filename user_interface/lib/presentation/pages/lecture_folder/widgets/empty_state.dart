// lib/presentation/pages/lecture_folder/widgets/empty_state.dart
import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(Icons.folder_outlined, size: 64, color: AppColors.universe.textComet),
              const SizedBox(height: 16),
              Text(
                'No folders yet', 
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: AppColors.universe.textStarlight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a folder to organize your lecture notes',
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // ボタン（FilledButtonはThemeのPrimaryを使うのでそのままでOK）
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Create folder'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.starGold,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}