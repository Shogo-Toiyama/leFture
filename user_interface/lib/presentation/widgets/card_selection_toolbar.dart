// lib/presentation/widgets/card_selection_toolbar.dart
//
// A GoodNotes-style toolbar shown at the top of Review Cards / Deep Notes
// pages, between the grid-view icon and the page counter. Shows reaction
// actions (Like / Dislike / Save) by default, and swaps to text-selection
// actions (Highlight / Note / Copy / Source) while a selection is active.
// Highlight / Note / Copy / Source are still UI-only placeholders.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class CardSelectionToolbar extends HookWidget {
  const CardSelectionToolbar({
    super.key,
    required this.hasSelection,
    this.accentColor,
    this.reaction,
    this.saved = false,
    this.onLike,
    this.onDislike,
    this.onSave,
  });

  final bool hasSelection;
  final Color? accentColor;

  // "like" / "dislike" / null
  final String? reaction;
  final bool saved;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onSave;

  static const _selectionItems = [
    _ToolbarItemData(icon: Icons.brush_outlined, label: 'Highlight'),
    _ToolbarItemData(icon: Icons.edit_note_rounded, label: 'Note'),
    _ToolbarItemData(icon: Icons.copy_rounded, label: 'Copy'),
    _ToolbarItemData(icon: Icons.description_outlined, label: 'Source'),
  ];

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.paper.textInk;

    final scrollController = useScrollController();
    final canScrollLeft = useState(false);
    final canScrollRight = useState(false);

    void updateFades() {
      if (!scrollController.hasClients) return;
      final position = scrollController.position;
      canScrollLeft.value = position.pixels > position.minScrollExtent + 1;
      canScrollRight.value = position.pixels < position.maxScrollExtent - 1;
    }

    final buttons = hasSelection
        ? [
            for (final item in _selectionItems)
              _ToolbarButton(icon: item.icon, label: item.label, color: color, onTap: () {}),
          ]
        : [
            _ToolbarButton(
              icon: reaction == 'like' ? Icons.favorite : Icons.favorite_border,
              label: 'Like',
              color: color,
              isActive: reaction == 'like',
              onTap: onLike,
            ),
            _ToolbarButton(
              icon: reaction == 'dislike' ? Icons.thumb_down : Icons.thumb_down_alt_outlined,
              label: 'Dislike',
              color: color,
              isActive: reaction == 'dislike',
              onTap: onDislike,
            ),
            _ToolbarButton(
              icon: saved ? Icons.bookmark : Icons.bookmark_border,
              label: 'Save',
              color: color,
              isActive: saved,
              onTap: onSave,
            ),
          ];

    useEffect(() {
      scrollController.addListener(updateFades);
      WidgetsBinding.instance.addPostFrameCallback((_) => updateFades());
      return () => scrollController.removeListener(updateFades);
    }, [scrollController, hasSelection]);

    return SizedBox(
      height: 36,
      child: LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateFades());

          final content = SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 20),
                      buttons[i],
                    ],
                  ],
                ),
              ),
            ),
          );

          if (!canScrollLeft.value && !canScrollRight.value) {
            return content;
          }

          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  canScrollLeft.value ? 0.08 : 0.0,
                  canScrollRight.value ? 0.92 : 1.0,
                  1.0,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: content,
          );
        },
      ),
    );
  }
}

class _ToolbarItemData {
  const _ToolbarItemData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.color,
    this.isActive = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? color : color.withValues(alpha: 0.75);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: effectiveColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: effectiveColor,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
