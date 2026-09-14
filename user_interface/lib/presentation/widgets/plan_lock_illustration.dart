import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/utils/annotation_text_utils.dart' show colorToHex;

/// 機能ロック表示用の、少しファンシーな鍵アイコン。
/// オンボーディングのイラスト(onboarding_illustrations.dart)と同じ手法
/// (生SVG文字列 + SvgPicture.string、グラデーション+グロー+アクセントの
/// コズミックなスタイル)で描画する。解放に必要なプランの色(plan_theme.dartの
/// planThemeColor相当)をそのままグラデーション・グロー色として渡す。
class PlanLockIllustration extends StatelessWidget {
  const PlanLockIllustration({super.key, required this.color, this.size = 96});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = colorToHex(color);
    final light = colorToHex(Color.lerp(color, Colors.white, 0.45) ?? color);

    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(_lockSvg(base: base, light: light)),
    );
  }
}

String _lockSvg({required String base, required String light}) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" fill="none">
  <defs>
    <linearGradient id="lockGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="$light"/>
      <stop offset="100%" stop-color="$base"/>
    </linearGradient>
    <radialGradient id="lockGlow" cx="50%" cy="44%" r="58%">
      <stop offset="0%" stop-color="$base" stop-opacity="0.38"/>
      <stop offset="60%" stop-color="$base" stop-opacity="0.14"/>
      <stop offset="100%" stop-color="$base" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="lockGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="$light" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="$base" stop-opacity="0.06"/>
    </linearGradient>
  </defs>

  <!-- アンビエントグロー -->
  <circle cx="48" cy="46" r="42" fill="url(#lockGlow)"/>

  <!-- シャックル(弦) -->
  <path d="M32 44 V32 a16 16 0 0 1 32 0 V44" stroke="url(#lockGrad)" stroke-width="6" stroke-linecap="round" fill="none"/>

  <!-- 本体 -->
  <rect x="22" y="42" width="52" height="40" rx="13" fill="#0E1E38" stroke="url(#lockGrad)" stroke-width="2"/>
  <rect x="22" y="42" width="52" height="40" rx="13" fill="url(#lockGlass)"/>

  <!-- 鍵穴 -->
  <circle cx="48" cy="58" r="5.5" fill="url(#lockGrad)"/>
  <rect x="45.4" y="61" width="5.2" height="11" rx="2.2" fill="url(#lockGrad)"/>

  <!-- キラキラアクセント -->
  <path d="M78 20 l2.2 5.4 5.4 2.2 -5.4 2.2 -2.2 5.4 -2.2 -5.4 -5.4 -2.2 5.4 -2.2 z" fill="$light" opacity="0.85"/>
  <circle cx="16" cy="62" r="2.2" fill="$light" opacity="0.7"/>
  <circle cx="22" cy="24" r="1.4" fill="$light" opacity="0.55"/>
</svg>
''';
