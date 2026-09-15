// lib/presentation/widgets/horizontal_scroll_drag_guard.dart
//
// Lets a horizontally-scrollable region (e.g. a code block) win a drag
// against an ancestor's own horizontal-drag gesture (e.g. swipe-to-next-card)
// even though both recognizers would otherwise enter the same gesture arena.
//
// A pointer-down inside [HorizontalScrollDragGuard] marks the guard active
// *before* the ancestor's recognizer decides whether to accept the pointer
// (pointer-down events dispatch depth-first, so the descendant's [Listener]
// fires first). The ancestor then rejects the pointer outright via
// [SwipeAwareHorizontalDragRecognizer.isPointerAllowed].
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class HorizontalScrollDragGuard extends StatelessWidget {
  const HorizontalScrollDragGuard({super.key, required this.child});

  final Widget child;

  static int _activePointers = 0;

  static bool get isActive => _activePointers > 0;

  static void _increment() => _activePointers++;

  static void _decrement() {
    if (_activePointers > 0) _activePointers--;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _increment(),
      onPointerUp: (_) => _decrement(),
      onPointerCancel: (_) => _decrement(),
      child: child,
    );
  }
}

/// A [HorizontalDragGestureRecognizer] that declines any pointer that came
/// down inside an active [HorizontalScrollDragGuard], so nested horizontally
/// scrollable content (code blocks) can be scrolled instead of triggering the
/// ancestor's swipe gesture.
class SwipeAwareHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  SwipeAwareHorizontalDragRecognizer({super.debugOwner});

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (HorizontalScrollDragGuard.isActive) return false;
    return super.isPointerAllowed(event);
  }
}
