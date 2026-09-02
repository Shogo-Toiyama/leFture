// lib/presentation/widgets/playback_speed_menu.dart

import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 再生速度を選択するためのカスタムドロップダウン/ポップアップメニュー。
/// ボタンの直上を起点に「下から上へ」美しくアニメーション展開。
/// ライトテーマ（Paper / DeepGold）とダークテーマ（Universe / StarGold）の両方に対応。
class PlaybackSpeedMenu extends StatelessWidget {
  const PlaybackSpeedMenu({
    super.key,
    required this.speed,
    required this.onSpeedSelected,
    this.isDark = false,
    this.speeds = const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
  });

  final double speed;
  final ValueChanged<double> onSpeedSelected;
  final bool isDark;
  final List<double> speeds;

  static String formatSpeed(double val) {
    if (val == val.truncateToDouble()) {
      return '${val.toInt()}.0x';
    }
    return '${val}x';
  }

  void _showMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final buttonTopLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final overlaySize = overlay.size;

    final activeColor = isDark ? AppColors.starGold : AppColors.deepGold;
    final textColor = isDark ? AppColors.universe.textStarlight : AppColors.paper.textInk;
    final secondaryTextColor = isDark ? AppColors.universe.textComet : AppColors.paper.textPencil;
    final menuBgColor = isDark ? const Color(0xFF161922) : AppColors.paper.surface;
    final borderColor = isDark ? AppColors.universe.glassBorder : AppColors.paper.line;

    final selected = await showGeneralDialog<double>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curvedAnim = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return Stack(
          children: [
            // 背景タップ領域
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),

            // ボタンの直上に下から上へ展開するメニュー
            Positioned(
              left: buttonTopLeft.dx.clamp(8.0, overlaySize.width - 148.0),
              bottom: overlaySize.height - buttonTopLeft.dy + 6.0,
              width: 140,
              child: ScaleTransition(
                alignment: Alignment.bottomLeft,
                scale: curvedAnim,
                child: FadeTransition(
                  opacity: curvedAnim,
                  child: Material(
                    color: menuBgColor,
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: borderColor, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < speeds.length; i++) ...[
                          _SpeedMenuItem(
                            speed: speeds[i],
                            currentSpeed: speed,
                            activeColor: activeColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            formatSpeed: formatSpeed,
                            onTap: () => Navigator.of(context).pop(speeds[i]),
                          ),
                          if (i < speeds.length - 1)
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: borderColor.withValues(alpha: 0.5),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      onSpeedSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? AppColors.starGold : AppColors.deepGold;

    return GestureDetector(
      onTap: () => _showMenu(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.universe.glassWhiteLow
              : AppColors.paper.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.universe.glassBorder : AppColors.paper.line,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              formatSpeed(speed),
              style: TextStyle(
                color: activeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_up_rounded,
              size: 16,
              color: activeColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedMenuItem extends StatelessWidget {
  const _SpeedMenuItem({
    required this.speed,
    required this.currentSpeed,
    required this.activeColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.formatSpeed,
    required this.onTap,
  });

  final double speed;
  final double currentSpeed;
  final Color activeColor;
  final Color textColor;
  final Color secondaryTextColor;
  final String Function(double) formatSpeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = speed == currentSpeed;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Text(
              formatSpeed(speed),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : textColor,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 16,
                color: activeColor,
              )
            else if (speed == 1.0)
              Text(
                '1.0x',
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryTextColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
