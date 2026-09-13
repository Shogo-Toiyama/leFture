// lib/presentation/pages/profile/plans_page.dart
import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'widgets/plan_selection_view.dart';

/// クレジット配布プラン一覧画面。実際のUI/ロジックは[PlanSelectionView]に
/// あり、このページはそれをNavigatorのpushで開ける単体画面として包む。
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void handleBack() => Navigator.of(context).pop();

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: PlanSelectionView(
        header: _PlansPageHeader(onBack: handleBack, tagline: l10n.plansTagline),
        onBack: handleBack,
      ),
    );
  }
}

class _PlansPageHeader extends StatelessWidget {
  const _PlansPageHeader({required this.onBack, required this.tagline});

  final VoidCallback onBack;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: onBack,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Plans',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFF2F2F2),
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tagline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
