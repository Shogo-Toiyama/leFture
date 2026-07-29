// lib/presentation/pages/introduction/widgets/intro_reveal.dart
import 'package:flutter/material.dart';

/// Introductionの各スライドで使う、「下から浮かび上がって現れる」共通の
/// 出現アニメーション。[visible]をtrueにした瞬間にフェード+スライドする。
class RiseIn extends StatelessWidget {
  const RiseIn({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
    this.slideFraction = 0.14,
  });

  final bool visible;
  final Widget child;
  final Duration duration;
  final double slideFraction;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : Offset(0, slideFraction),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
