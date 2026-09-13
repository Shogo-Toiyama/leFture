import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// プランごとのテーマカラー。
/// storeProductId (例: com.lefture.app.sub.starter) による判定を最優先し、
/// 未指定時は planName または文字列全体から判定する。
Color planThemeColor(String planName, {String? storeProductId}) {
  final target = (storeProductId != null && storeProductId.isNotEmpty)
      ? storeProductId.toLowerCase()
      : planName.toLowerCase();

  if (target.contains('premium') || target.contains('max')) {
    return const Color(0xFF7C4DFF);
  }
  if (target.contains('standard') || target.contains('core')) {
    return const Color(0xFFE11D48);
  }
  if (target.contains('starter') || target.contains('entry') || target.contains('lite')) {
    return AppColors.cosmicBlue;
  }
  return AppColors.starGold;
}

/// plan_icons/ 配下のアセットファイル名(拡張子込み)。
String planIconAsset(String planName, {String? storeProductId}) {
  final target = (storeProductId != null && storeProductId.isNotEmpty)
      ? storeProductId.toLowerCase()
      : planName.toLowerCase();

  if (target.contains('premium') || target.contains('max')) {
    return 'assets/images/plan_icons/galaxy.png';
  }
  if (target.contains('standard') || target.contains('core')) {
    return 'assets/images/plan_icons/solarsystem.png';
  }
  if (target.contains('starter') || target.contains('entry') || target.contains('lite')) {
    return 'assets/images/plan_icons/planet.png';
  }
  return 'assets/images/plan_icons/stardust.png';
}
