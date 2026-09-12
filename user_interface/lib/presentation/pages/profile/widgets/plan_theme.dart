import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// プランごとのテーマカラー。plan.nameでの文字列一致は、既存の
/// (plan.name == 'Standard')ハイライト判定と同じ方式を踏襲している。
Color planThemeColor(String planName) {
  switch (planName) {
    case 'Free':
      return AppColors.starGold;
    case 'Entry':
      return AppColors.cosmicBlue;
    case 'Standard':
      return const Color(0xFFE11D48);
    case 'Premium':
      return const Color(0xFF7C4DFF);
    default:
      return AppColors.starGold;
  }
}

/// plan_icons/ 配下のアセットファイル名(拡張子込み)。
String planIconAsset(String planName) {
  switch (planName) {
    case 'Free':
      return 'assets/images/plan_icons/stardust.png';
    case 'Entry':
      return 'assets/images/plan_icons/planet.png';
    case 'Standard':
      return 'assets/images/plan_icons/solarsystem.png';
    case 'Premium':
      return 'assets/images/plan_icons/galaxy.png';
    default:
      return 'assets/images/plan_icons/stardust.png';
  }
}
