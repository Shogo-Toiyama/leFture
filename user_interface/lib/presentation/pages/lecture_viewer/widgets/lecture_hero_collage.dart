import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/topic_image.dart';

class LectureHeroCollage extends ConsumerWidget {
  const LectureHeroCollage({
    super.key,
    required this.lectureId,
    this.slantWidth = 24.0,
    this.onTap,
    this.isActive = true,
  });

  final String lectureId;
  final double slantWidth;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));

    return topicsAsync.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(color: Colors.amber)),
      ),
      error: (err, stack) => const SizedBox.shrink(),
      data: (topics) {
        // Filter out empty/null paths
        final imagePaths = topics
            .map((t) => t.imagePath)
            .where((path) => path != null && path.trim().isNotEmpty)
            .cast<String>()
            .toList();

        if (imagePaths.isEmpty) {
          return const SizedBox.shrink();
        }

        final count = imagePaths.length;
        final images = watchTopicImages(
          ref,
          imagePaths,
          startRequests: isActive && ModalRoute.isCurrentOf(context) != false,
        );

        final collageWidget = Container(
          height: 180.0,
          width: double.infinity,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final segmentWidth = w / count;
                final slotSlant = count == 1
                    ? 0.0
                    : slantWidth.clamp(0.0, segmentWidth);
                final delta = slotSlant / 2;

                return Stack(
                  children: [
                    // Draw each slanted image slot
                    ...List.generate(count, (index) {
                      final path = imagePaths[index];

                      // Calculate X bounds of slot index
                      final double xStart = index == 0
                          ? 0.0
                          : (index * segmentWidth) - delta;
                      final double slotWidth = index == 0
                          ? segmentWidth + delta
                          : (index == count - 1
                                ? segmentWidth + delta
                                : segmentWidth + slotSlant);

                      return Positioned(
                        left: xStart,
                        top: 0,
                        bottom: 0,
                        child: _SlantedImageSlot(
                          imagePath: path,
                          images: images,
                          index: index,
                          totalCount: count,
                          segmentWidth: segmentWidth,
                          slantWidth: slotSlant,
                          slotWidth: slotWidth,
                          height: h,
                        ),
                      );
                    }),

                    // Draw premium divider lines overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: SlantedDividerPainter(
                            totalCount: count,
                            segmentWidth: segmentWidth,
                            slantWidth: slotSlant,
                            color: Colors.white.withValues(alpha: 0.25),
                            strokeWidth: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );

        if (onTap != null) {
          return GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: collageWidget,
          );
        }

        return collageWidget;
      },
    );
  }
}

class _SlantedImageSlot extends StatelessWidget {
  const _SlantedImageSlot({
    required this.imagePath,
    required this.images,
    required this.index,
    required this.totalCount,
    required this.segmentWidth,
    required this.slantWidth,
    required this.slotWidth,
    required this.height,
  });

  final String imagePath;
  final Map<String, AsyncValue<File>> images;
  final int index;
  final int totalCount;
  final double segmentWidth;
  final double slantWidth;
  final double slotWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = TopicImage(
      path: imagePath,
      images: images,
      placeholder: ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
    );

    return ClipPath(
      clipper: SlantedSlotClipper(
        index: index,
        totalCount: totalCount,
        segmentWidth: segmentWidth,
        slantWidth: slantWidth,
      ),
      child: SizedBox(width: slotWidth, height: height, child: child),
    );
  }
}

class SlantedSlotClipper extends CustomClipper<Path> {
  const SlantedSlotClipper({
    required this.index,
    required this.totalCount,
    required this.segmentWidth,
    required this.slantWidth,
  });

  final int index;
  final int totalCount;
  final double segmentWidth;
  final double slantWidth;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final delta = slantWidth / 2;

    if (totalCount <= 1) {
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    }

    final double xTl = 0;
    final double xTr = (index == totalCount - 1) ? w : segmentWidth;
    final double xBr = (index == totalCount - 1)
        ? w
        : (index == 0 ? segmentWidth + delta : segmentWidth + slantWidth);
    final double xBl = (index == 0) ? 0 : slantWidth;

    return Path()
      ..moveTo(xTl, 0)
      ..lineTo(xTr, 0)
      ..lineTo(xBr, h)
      ..lineTo(xBl, h)
      ..close();
  }

  @override
  bool shouldReclip(covariant SlantedSlotClipper oldClipper) {
    return oldClipper.index != index ||
        oldClipper.totalCount != totalCount ||
        oldClipper.segmentWidth != segmentWidth ||
        oldClipper.slantWidth != slantWidth;
  }
}

class SlantedDividerPainter extends CustomPainter {
  const SlantedDividerPainter({
    required this.totalCount,
    required this.segmentWidth,
    required this.slantWidth,
    required this.color,
    required this.strokeWidth,
  });

  final int totalCount;
  final double segmentWidth;
  final double slantWidth;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalCount <= 1) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final delta = slantWidth / 2;
    for (int i = 0; i < totalCount - 1; i++) {
      final xTop = (i + 1) * segmentWidth - delta;
      final xBottom = (i + 1) * segmentWidth + delta;
      canvas.drawLine(Offset(xTop, 0), Offset(xBottom, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant SlantedDividerPainter oldDelegate) {
    return oldDelegate.totalCount != totalCount ||
        oldDelegate.segmentWidth != segmentWidth ||
        oldDelegate.slantWidth != slantWidth ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
