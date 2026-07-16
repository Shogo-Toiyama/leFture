// lib/presentation/widgets/draggable_toolbar_card.dart
//
// Shared floating-card chrome for the Highlight/Note sub-toolbars: a white
// rounded card with a drag handle (":::") at the top-center that lets the
// user reposition it anywhere on screen. Always starts back at its default
// (top-center) position, since it's a fresh widget instance each time the
// popover is opened.
//
// Dragging repositions the card via an actual Positioned(left, top) --
// NOT a Transform -- so hit-testing moves along with it. A Transform-only
// offset leaves the widget's hit-test box at its original (pre-drag)
// location, which makes it un-tappable/un-draggable again after the user
// releases far from where it started.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class DraggableToolbarCard extends HookWidget {
  const DraggableToolbarCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cardKey = useMemoized(() => GlobalKey());
    // null until the user first drags; the card renders at its default
    // top-center position until then.
    final offset = useState<Offset?>(null);

    return LayoutBuilder(
      builder: (context, constraints) {
        void handlePanUpdate(DragUpdateDetails details) {
          final current = offset.value;
          if (current == null) {
            // Seed the absolute position from where the card is actually
            // rendered right now (top-center), so the drag continues from
            // under the finger instead of jumping.
            final renderBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
            final width = renderBox?.size.width ?? 0;
            final startLeft = (constraints.maxWidth - width) / 2;
            offset.value = Offset(startLeft, 4) + details.delta;
          } else {
            offset.value = current + details.delta;
          }
        }

        final card = _CardChrome(
          key: cardKey,
          onPanUpdate: handlePanUpdate,
          child: child,
        );

        return Stack(
          children: [
            Positioned(
              top: offset.value?.dy ?? 4,
              left: offset.value == null ? 0 : offset.value!.dx,
              right: offset.value == null ? 0 : null,
              child: offset.value == null ? Center(child: card) : card,
            ),
          ],
        );
      },
    );
  }
}

class _CardChrome extends StatelessWidget {
  const _CardChrome({super.key, required this.child, required this.onPanUpdate});

  final Widget child;
  final ValueChanged<DragUpdateDetails> onPanUpdate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onPanUpdate,
              child: const SizedBox(
                width: 48,
                height: 20,
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 18,
                  color: Colors.black26,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
