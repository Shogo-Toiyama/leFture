// lib/presentation/pages/home/widgets/tutorial_lecture_callout.dart
//
// チュートリアル講義のタイルだけを、パルスする枠+吹き出しで軽く強調する
// ウィジェット。「一度でも開かれたか」は lastAccessedAt の有無で判定するので、
// このウィジェット自体は表示のON/OFFを親から渡されるだけで済む(状態は持たない)。
import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class TutorialLectureCallout extends StatefulWidget {
  const TutorialLectureCallout({
    super.key,
    required this.child,
    this.message,
    this.borderRadius = 18,
    this.badgeTop = -14,
    this.badgeRight = 16,
    this.badgeLeft,
  });

  final Widget child;
  final String? message;
  final double borderRadius;
  final double badgeTop;
  final double? badgeRight;
  final double? badgeLeft;

  @override
  State<TutorialLectureCallout> createState() => _TutorialLectureCalloutState();
}

class _TutorialLectureCalloutState extends State<TutorialLectureCallout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final glow = 0.3 + (_controller.value * 0.5);
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: AppColors.starGold.withValues(alpha: glow),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.starGold.withValues(alpha: glow * 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: widget.child,
        ),
        Positioned(
          top: widget.badgeTop,
          right: widget.badgeRight,
          left: widget.badgeLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.starGold,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              widget.message ?? l10n.homeTutorialCalloutMessage,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
