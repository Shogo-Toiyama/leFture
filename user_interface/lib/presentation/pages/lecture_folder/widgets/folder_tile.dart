import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.name,
    required this.svgAssetPath,
    required this.isFavorite,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final String name;
  final String svgAssetPath;
  final bool isFavorite;

  final VoidCallback onTap;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;
  final Future<void> Function(bool newValue) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            // 中身
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SvgPicture.asset(
                        svgAssetPath,
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),

            // 右上：お気に入り表示（任意）
            Positioned(
              top: 8,
              left: 8,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: isFavorite ? 1 : 0,
                child: const Icon(Icons.star_rounded, size: 18),
              ),
            ),

            // 右上：3点メニュー
            Positioned(
              top: 2,
              right: 2,
              child: _FolderMenuButton(
                isFavorite: isFavorite,
                onRename: onRename,
                onDelete: onDelete,
                onToggleFavorite: onToggleFavorite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderMenuButton extends StatelessWidget {
  const _FolderMenuButton({
    required this.isFavorite,
    required this.onRename,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final bool isFavorite;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;
  final Future<void> Function(bool newValue) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Folder actions',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) async {
        if (value == 'rename') {
          await onRename();
        } else if (value == 'delete') {
          await onDelete();
        } else if (value == 'favorite') {
          await onToggleFavorite(!isFavorite);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, size: 18),
              const SizedBox(width: 8),
              Text(isFavorite ? 'Unfavorite' : 'Favorite'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 18),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }
}
