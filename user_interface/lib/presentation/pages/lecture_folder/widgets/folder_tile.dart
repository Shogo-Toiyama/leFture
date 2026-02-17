import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

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
    return Container(
      decoration: BoxDecoration(
        // 半透明の白ガラス
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        // 薄いボーダーで輪郭を出す
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
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
                          colorFilter: ColorFilter.mode(AppColors.starGold, BlendMode.srcIn),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        // 文字は星屑の白
                        color: AppColors.universe.textStarlight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // 右上：お気に入り表示
              Positioned(
                top: 8,
                left: 8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: isFavorite ? 1 : 0,
                  child: const Icon(Icons.star_rounded, size: 18, color: AppColors.starGold),
                ),
              ),

              // 右上：3点メニュー
              Positioned(
                top: 0,
                right: 0,
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
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.white54),
      // メニューの背景色などはTheme依存になるが、
      // AppTheme.main(Dark)を使っていれば自然とダークになるはず
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
              Icon(Icons.delete_outline, size: 18, color: AppColors.correctionRed),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: AppColors.correctionRed)),
            ],
          ),
        ),
      ],
    );
  }
}