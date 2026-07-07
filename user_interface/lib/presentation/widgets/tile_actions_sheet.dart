import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

Future<void> showTileActionsSheet({
  required BuildContext context,
  required String title,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: const Color(0xFF161829),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white),
              title: const Text('Edit', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.of(context).pop();
                onEdit();
              },
            ),
            Divider(color: AppColors.universe.glassBorder, height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.correctionRed),
              title: const Text('Delete', style: TextStyle(color: AppColors.correctionRed, fontSize: 14)),
              onTap: () {
                Navigator.of(context).pop();
                onDelete();
              },
            ),
          ],
        ),
      );
    },
  );
}
