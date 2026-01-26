// lib/presentation/pages/lecture_folder/widgets/breadcrumb_bar.dart
import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
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
                  // onTap: isLast ? null : () => onTapCrumb(i),
                  onTap: canTap ? () => onTapCrumb(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      crumbs[i],
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isLast ? theme.colorScheme.primary : null,
                        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
