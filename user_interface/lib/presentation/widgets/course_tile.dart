import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:lecture_companion_ui/presentation/widgets/tile_actions_sheet.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';

class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    this.showChevron = true,
    this.onEdit,
    this.onDelete,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final Course course;
  final bool showChevron;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final themeColor = CourseStyleHelper.hexToColor(course.color, fallback: AppColors.starGold);
    final iconData = CourseStyleHelper.getIcon(course.icon);

    return GestureDetector(
      onTap: () => context.push('${AppRoutes.coursesRootPath}/c/${course.id}'),
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
                    title: l10n.courseDeleteDialogTitle,
                    message: l10n.courseDeleteDialogMessage(course.displayTitle),
                    confirmLabel: l10n.commonDeleteButton,
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
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.3),
                  width: 1.0,
                ),
              ),
              child: Icon(
                iconData,
                color: themeColor,
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
