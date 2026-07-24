import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class RecordingTimerChip extends ConsumerWidget {
  const RecordingTimerChip({super.key});

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return [
      if (hours > 0) hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(recordingControllerProvider);
    final isRecording = recordingState.isRecording;
    final isPaused = recordingState.isPaused;

    if (!isRecording && !isPaused) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => context.push(AppRoutes.recording),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isRecording ? AppColors.correctionRed : AppColors.alertAmber,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRecording ? Icons.mic : Icons.pause,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _formatDuration(recordingState.elapsedSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}