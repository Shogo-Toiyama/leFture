import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class RecordingTimerChip extends StatelessWidget {
  const RecordingTimerChip({super.key});

  @override
  Widget build(BuildContext context) {
    const isRecording = true; 
    const isPaused = false;

    if (!isRecording && !isPaused) {
      return SizedBox.shrink();
    }
    return GestureDetector(
      onTap: ()=>{context.push(AppRoutes.recording)},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
            // 点滅するアイコンの演出（今回は静止画）
            Icon(
              isRecording ? Icons.mic : Icons.pause,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            const Text(
              '00:12:34', // Fake Time
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()], // 数字の幅を揃える
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}