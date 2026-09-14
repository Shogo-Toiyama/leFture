import 'package:flutter/material.dart';
import 'package:lefture/domain/plan_features.dart' as plan_features;
import 'package:lefture/presentation/themes/app_colors.dart';

/// プランごとのテーマカラー。tier_level(0=Free, 1=Lite, 2=Core, 3=Max)だけで
/// 判定する — 以前はplanName/storeProductIdの文字列に'premium'/'max'等が
/// 含まれるかで判定していたが、プラン名は今後マーケティング都合で変わり得る一方
/// tier_levelはDB上の安定した整数なので、判定はすべてこちらに統一した。
Color planThemeColor(int tierLevel) {
  switch (tierLevel) {
    case plan_features.tierMax:
      return const Color(0xFF7C4DFF);
    case plan_features.tierCore:
      return const Color(0xFFE11D48);
    case plan_features.tierLite:
      return AppColors.cosmicBlue;
    default:
      return AppColors.starGold;
  }
}

/// plan_icons/ 配下のアセットファイル名(拡張子込み)。判定方針はplanThemeColorと同じ
/// (tier_levelのみ)。
String planIconAsset(int tierLevel) {
  switch (tierLevel) {
    case plan_features.tierMax:
      return 'assets/images/plan_icons/galaxy.png';
    case plan_features.tierCore:
      return 'assets/images/plan_icons/solarsystem.png';
    case plan_features.tierLite:
      return 'assets/images/plan_icons/planet.png';
    default:
      return 'assets/images/plan_icons/stardust.png';
  }
}
