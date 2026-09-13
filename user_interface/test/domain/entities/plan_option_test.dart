import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_theme.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:flutter/material.dart';

void main() {
  group('PlanOption and planTheme resolution by storeProductId', () {
    test('resolves Starter / Lite tier correctly by storeProductId', () {
      final plan = PlanOption.fromJson({
        'id': 'plan_lite',
        'name': 'Lite',
        'monthly_credit_amount': 1200000000,
        'claim_mode': 'store_purchase',
        'store_product_id': 'com.lefture.app.sub.starter',
      });

      expect(plan.tierLevel, 1);
      expect(plan.isStarterTier, isTrue);
      expect(plan.isStandardTier, isFalse);
      expect(plan.isPremiumTier, isFalse);
      expect(planThemeColor(plan.name, storeProductId: plan.storeProductId), AppColors.cosmicBlue);
      expect(planIconAsset(plan.name, storeProductId: plan.storeProductId), 'assets/images/plan_icons/planet.png');
    });

    test('resolves Standard / Core tier correctly by storeProductId', () {
      final plan = PlanOption.fromJson({
        'id': 'plan_core',
        'name': 'Core',
        'monthly_credit_amount': 2000000000,
        'claim_mode': 'store_purchase',
        'store_product_id': 'com.lefture.app.sub.standard',
      });

      expect(plan.tierLevel, 2);
      expect(plan.isStarterTier, isFalse);
      expect(plan.isStandardTier, isTrue);
      expect(plan.isPremiumTier, isFalse);
      expect(planThemeColor(plan.name, storeProductId: plan.storeProductId), const Color(0xFFE11D48));
      expect(planIconAsset(plan.name, storeProductId: plan.storeProductId), 'assets/images/plan_icons/solarsystem.png');
    });

    test('resolves Premium / Max tier correctly by storeProductId', () {
      final plan = PlanOption.fromJson({
        'id': 'plan_max',
        'name': 'Max',
        'monthly_credit_amount': 3000000000,
        'claim_mode': 'store_purchase',
        'store_product_id': 'com.lefture.app.sub.premium',
      });

      expect(plan.tierLevel, 3);
      expect(plan.isStarterTier, isFalse);
      expect(plan.isStandardTier, isFalse);
      expect(plan.isPremiumTier, isTrue);
      expect(planThemeColor(plan.name, storeProductId: plan.storeProductId), const Color(0xFF7C4DFF));
      expect(planIconAsset(plan.name, storeProductId: plan.storeProductId), 'assets/images/plan_icons/galaxy.png');
    });

    test('resolves Free tier when storeProductId is null', () {
      final plan = PlanOption.fromJson({
        'id': 'plan_free',
        'name': 'Free',
        'monthly_credit_amount': 1500000000,
        'claim_mode': 'self_serve',
        'store_product_id': null,
      });

      expect(plan.tierLevel, 0);
      expect(plan.isFreeTier, isTrue);
      expect(planThemeColor(plan.name, storeProductId: plan.storeProductId), AppColors.starGold);
      expect(planIconAsset(plan.name, storeProductId: plan.storeProductId), 'assets/images/plan_icons/stardust.png');
    });
  });
}
