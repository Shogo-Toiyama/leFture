import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.crumbs,
    required this.onTapCrumb,
  });

  final List<String> crumbs;
  final void Function(int index) onTapCrumb;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // 背景は透明、下のボーダーだけ薄く引く
        color: Colors.transparent, 
        border: Border(bottom: BorderSide(color: AppColors.universe.glassBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(crumbs.length, (i) {
            final isLast = i == crumbs.length - 1;
            final canTap = !isLast || crumbs.length == 1;
            return Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: canTap ? () => onTapCrumb(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      crumbs[i],
                      style: TextStyle(
                        // 最後（現在地）はゴールド、それ以外はComet色
                        color: isLast ? AppColors.starGold : AppColors.universe.textComet,
                        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.chevron_right, size: 18, color: AppColors.universe.textComet),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}