// lib/presentation/widgets/highlight_sub_toolbar.dart
//
// Floating popover shown when the "Highlight" button is tapped in
// CardSelectionToolbar.
//  - mode row (always visible): line / wave / marker / eraser, each
//    previewed as a stylized "Aa" glyph in the current color, plus a
//    swatch button.
//  - color row (tucked below, shown when the swatch is tapped): a 3x3
//    grid of CourseStyleHelper.presetColors.
// UI only -- selecting a mode does not persist anything yet.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/widgets/draggable_toolbar_card.dart';

typedef HighlightMode = String; // "line" | "wave" | "marker" | "eraser"

class HighlightSubToolbar extends HookWidget {
  const HighlightSubToolbar({
    super.key,
    required this.color,
    required this.onColorChanged,
    this.activeMode,
    this.onModeSelected,
  });

  final Color color;
  final ValueChanged<Color> onColorChanged;
  final HighlightMode? activeMode;
  final ValueChanged<HighlightMode>? onModeSelected;

  @override
  Widget build(BuildContext context) {
    final showColorPicker = useState(false);

    return DraggableToolbarCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeRow(
            color: color,
            activeMode: activeMode,
            onModeSelected: onModeSelected,
            isColorPickerOpen: showColorPicker.value,
            onSwatchTap: () => showColorPicker.value = !showColorPicker.value,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: showColorPicker.value
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _ColorGrid(
                      selectedColor: color,
                      onColorSelected: onColorChanged,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.color,
    required this.activeMode,
    required this.onModeSelected,
    required this.isColorPickerOpen,
    required this.onSwatchTap,
  });

  final Color color;
  final HighlightMode? activeMode;
  final ValueChanged<HighlightMode>? onModeSelected;
  final bool isColorPickerOpen;
  final VoidCallback onSwatchTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(
          mode: 'line',
          color: color,
          isActive: activeMode == 'line',
          onTap: () => onModeSelected?.call('line'),
          preview: _AaPreview(style: _AaStyle.line, color: color),
        ),
        _ModeButton(
          mode: 'wave',
          color: color,
          isActive: activeMode == 'wave',
          onTap: () => onModeSelected?.call('wave'),
          preview: _AaPreview(style: _AaStyle.wave, color: color),
        ),
        _ModeButton(
          mode: 'marker',
          color: color,
          isActive: activeMode == 'marker',
          onTap: () => onModeSelected?.call('marker'),
          preview: _AaPreview(style: _AaStyle.marker, color: color),
        ),
        _ModeButton(
          mode: 'eraser',
          color: color,
          isActive: activeMode == 'eraser',
          onTap: () => onModeSelected?.call('eraser'),
          preview: Icon(Icons.auto_fix_off_rounded, size: 20, color: Colors.black54),
        ),
        Container(
          width: 1,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: Colors.black12,
        ),
        _SwatchButton(color: color, isActive: isColorPickerOpen, onTap: onSwatchTap),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.color,
    required this.isActive,
    required this.onTap,
    required this.preview,
  });

  final String mode;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isActive ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: isActive
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: 1.5),
                  )
                : null,
            child: preview,
          ),
        ),
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({required this.color, required this.isActive, required this.onTap});

  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? Colors.black.withValues(alpha: 0.06) : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? Colors.black54 : Colors.black12,
                width: isActive ? 1.5 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({
    required this.selectedColor,
    required this.onColorSelected,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  @override
  Widget build(BuildContext context) {
    final colors = CourseStyleHelper.presetColors;
    return SizedBox(
      width: 3 * 44,
      child: Wrap(
        children: [
          for (final c in colors)
            SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onColorSelected(c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selectedColor == c ? Colors.black87 : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: selectedColor == c
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _AaStyle { line, wave, marker }

class _AaPreview extends StatelessWidget {
  const _AaPreview({required this.style, required this.color});

  final _AaStyle style;
  final Color color;

  static const _textStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.black87,
    height: 1.0,
  );

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case _AaStyle.marker:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('Aa', style: _textStyle),
        );
      case _AaStyle.line:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aa', style: _textStyle),
            const SizedBox(height: 2),
            Container(width: 18, height: 2.5, color: color),
          ],
        );
      case _AaStyle.wave:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aa', style: _textStyle),
            const SizedBox(height: 1),
            CustomPaint(size: const Size(18, 5), painter: _WavePainter(color)),
          ],
        );
    }
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(0, size.height / 2);
    const bumps = 3;
    final step = size.width / bumps;
    for (var i = 0; i < bumps; i++) {
      final x1 = step * i + step / 2;
      final y1 = i.isEven ? 0.0 : size.height;
      final x2 = step * (i + 1);
      final y2 = size.height / 2;
      path.quadraticBezierTo(x1, y1, x2, y2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => oldDelegate.color != color;
}
