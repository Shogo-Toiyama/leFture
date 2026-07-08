// lib/presentation/widgets/custom_scrollbar.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../themes/app_colors.dart';

class CustomScrollbar extends HookConsumerWidget {
  const CustomScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.totalExtent,
  });

  final ScrollController controller;
  final Widget child;

  /// The scrollable content's true total (unclamped) extent, if already known
  /// exactly ahead of time (e.g. precomputed row heights for a lazily-built
  /// ListView). When provided, this is used instead of
  /// `ScrollPosition.maxScrollExtent` for the thumb's size/position math.
  ///
  /// For a lazily-built list (ListView.builder), `maxScrollExtent` is only an
  /// ESTIMATE that Flutter keeps revising as more items get measured while
  /// scrolling — every revision (e.g. each time an item scrolls off-screen
  /// and a new one needs measuring) shifts the thumb, even when the caller
  /// already knows the exact total. Passing it here bypasses that estimate
  /// entirely, so the thumb is exact and stable from the very first frame.
  final double? totalExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDragging = useState<bool>(false);
    final isVisible = useState<bool>(false);
    final fadeTimer = useRef<Timer?>(null);

    // Last maxScrollExtent actually used to render the thumb. For lazily-built
    // lists (ListView.builder), maxScrollExtent is an ESTIMATE that keeps
    // getting revised by small amounts as more items are measured while
    // scrolling. Reacting to every tiny revision makes the thumb visibly
    // twitch/sway even though nothing meaningfully changed. We only adopt a
    // new estimate once it moves far enough from the last one to matter;
    // small noise is ignored and the thumb holds its last stable geometry.
    final stableMaxScroll = useRef<double?>(null);

    // Only purpose of this listener: show the scrollbar and start the fade-out
    // timer on scroll. Scroll metrics are intentionally NOT cached here —
    // they are read fresh from controller.position inside AnimatedBuilder.
    useEffect(() {
      void onScroll() {
        if (!isDragging.value) {
          isVisible.value = true;
          fadeTimer.value?.cancel();
          fadeTimer.value = Timer(const Duration(milliseconds: 1500), () {
            isVisible.value = false;
          });
        }
      }

      controller.addListener(onScroll);
      return () {
        controller.removeListener(onScroll);
        fadeTimer.value?.cancel();
      };
    }, [controller]);

    // AnimatedBuilder rebuilds only its builder() on every scroll tick,
    // reading metrics directly from controller.position each time — so it
    // always reflects the true current state even when content height changes.
    //
    // IMPORTANT: the builder below always returns the SAME top-level shape —
    // Stack(children: [child, thumbOverlay]) — never a bare `child`. Early on
    // (before the controller is attached / metrics are known), returning
    // `child` directly and later switching to `Stack(children: [child, ...])`
    // once metrics become available would change the WIDGET TYPE at this
    // position in the tree (SingleChildScrollView -> Stack). Flutter can't
    // reuse an Element across a type change, so it tears down and recreates
    // the whole scrollable subtree — including its ScrollPosition and the
    // GestureRecognizer currently tracking an in-progress drag. That silently
    // orphans the user's first touch mid-gesture: the recognizer holding the
    // drag no longer belongs to a live tree, so further pointer moves do
    // nothing, while the scrollbar still renders (since the rebuild that
    // introduces the Stack is exactly what happens to trigger it). Always
    // returning the same Stack shape (with an empty overlay when there's
    // nothing to show yet) keeps the scrollable's Element stable across the
    // whole session, so gestures are never interrupted mid-flight.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        Widget overlay = const SizedBox.shrink();

        if (controller.hasClients) {
          final pos = controller.position;
          final offset = pos.pixels;
          final H = pos.viewportDimension;

          double maxScroll;
          if (totalExtent != null) {
            // Exact, precomputed — no estimate involved, so no smoothing needed.
            maxScroll = (totalExtent! - H).clamp(0.0, double.infinity);
          } else {
            final rawMaxScroll = pos.maxScrollExtent;
            // Adopt the new estimate only if it moved enough to matter (2% of
            // the last stable value, or 20px, whichever is larger). Otherwise
            // keep rendering with the last stable value so tiny estimate
            // noise from lazy layout doesn't make the thumb sway.
            final last = stableMaxScroll.value;
            if (last == null ||
                (rawMaxScroll - last).abs() >
                    (last * 0.02).clamp(20.0, double.infinity)) {
              stableMaxScroll.value = rawMaxScroll;
            }
            maxScroll = stableMaxScroll.value!;
          }

          if (maxScroll > 0.0 && H > 0.0) {
            final thumbHeight = ((H * H) / (H + maxScroll)).clamp(40.0, 150.0);
            final scrollProgress = (offset / maxScroll).clamp(0.0, 1.0);
            final thumbTop = scrollProgress * (H - thumbHeight);

            overlay = Positioned(
              right: 4,
              top: thumbTop,
              width: 24,
              height: thumbHeight,
              // While hidden, this overlay must not intercept touches: an
              // Opacity of 0 only stops painting, not hit-testing, so
              // without this guard the invisible thumb would still steal
              // touches that land on this strip.
              child: IgnorePointer(
                ignoring: !(isVisible.value || isDragging.value),
                child: AnimatedOpacity(
                  opacity: isVisible.value || isDragging.value ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: GestureDetector(
                    onVerticalDragStart: (_) {
                      isDragging.value = true;
                      isVisible.value = true;
                      fadeTimer.value?.cancel();
                    },
                    onVerticalDragUpdate: (details) {
                      if (!controller.hasClients) return;
                      final availableTrack = H - thumbHeight;
                      if (availableTrack <= 0) return;
                      final dragRatio = details.primaryDelta! / availableTrack;
                      final targetOffset =
                          (controller.offset + dragRatio * maxScroll).clamp(
                            0.0,
                            maxScroll,
                          );
                      controller.jumpTo(targetOffset);
                    },
                    onVerticalDragEnd: (_) {
                      isDragging.value = false;
                      fadeTimer.value?.cancel();
                      fadeTimer.value = Timer(
                        const Duration(milliseconds: 1500),
                        () {
                          isVisible.value = false;
                        },
                      );
                    },
                    child: Container(
                      width: 24, // Touch target
                      height: thumbHeight,
                      color: Colors.transparent,
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 8, // Visual thumb
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: AppColors.deepGold.withValues(
                            alpha: isDragging.value ? 0.8 : 0.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        return Stack(children: [child, overlay]);
      },
    );
  }
}
