// lib/presentation/widgets/language_header_button.dart
import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// App-wide top-right language selection button shared by Introduction,
/// SignIn, SignUp, and Onboarding pages.
class LanguageHeaderButton extends StatelessWidget {
  const LanguageHeaderButton({super.key});

  static Future<void> openLanguageSheet(BuildContext context) async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          const LanguageSelectionSheet(mode: LanguageSheetMode.display),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final buttonSize = isTablet ? 46.0 : 38.0;
    final iconSize = isTablet ? 24.0 : 20.0;
    final l10n = AppLocalizations.of(context);

    return Material(
      color: AppColors.universe.glassWhiteLow,
      shape: const CircleBorder(side: BorderSide(color: Color(0x1CFFFFFF))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => openLanguageSheet(context),
        child: Tooltip(
          message: l10n.introLanguageButton,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              Icons.language_rounded,
              size: iconSize,
              color: AppColors.universe.textStarlight,
            ),
          ),
        ),
      ),
    );
  }
}
