import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:lecture_companion_ui/presentation/widgets/tile_actions_sheet.dart';

class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    this.showChevron = true,
    this.onEdit,
    this.onDelete,
  });

  final Course course;
  final bool showChevron;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.notesRootPath}/c/${course.id}'),
      onLongPress: (onEdit != null || onDelete != null)
          ? () => showTileActionsSheet(
                context: context,
                title: course.displayTitle,
                onEdit: () {
                  if (onEdit != null) onEdit!();
                },
                onDelete: () async {
                  final confirm = await showCustomDialog(
                    context: context,
                    title: 'Delete Course?',
                    message: 'Are you sure you want to delete "${course.displayTitle}"? All lectures inside this course will be unassigned.',
                    confirmLabel: 'Delete',
                    icon: Icons.delete_outline,
                    isDestructive: true,
                  );
                  if (confirm == true && onDelete != null) {
                    onDelete!();
                  }
                },
              )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school_outlined,
                color: AppColors.starGold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                course.displayTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right,
                color: AppColors.universe.textComet,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
