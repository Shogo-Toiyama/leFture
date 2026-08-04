// lib/core/utils/moment_display_utils.dart

import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class MomentDisplayUtils {
  /// momentType ('fun', 'difficult', 'revisit', 'note') に応じたアイコン、カラー、デフォルトラベルを返す。
  static (IconData, Color, String) getMomentDisplay(String momentType) {
    switch (momentType) {
      case 'interesting':
        return (Icons.star_rounded, AppColors.starGold, 'Interesting moment');
      case 'difficult':
        return (Icons.help_rounded, AppColors.cosmicBlue, 'Difficult');
      case 'revisit':
        return (Icons.bookmark_rounded, AppColors.growthGreen, 'Revisit later');
      case 'note':
        return (Icons.edit_note_rounded, AppColors.deepGold, 'Note');
      default:
        return (
          Icons.emoji_objects_rounded,
          AppColors.paper.textPencil,
          momentType,
        );
    }
  }
}
