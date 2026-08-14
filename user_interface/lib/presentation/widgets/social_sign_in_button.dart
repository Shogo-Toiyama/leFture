import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Multi-color Google "G" mark, embedded as SVG so no extra asset file is needed.
const _googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z"/>
  <path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z"/>
  <path fill="#FBBC05" d="M11.69 28.18c-.44-1.32-.69-2.73-.69-4.18s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z"/>
  <path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z"/>
</svg>
''';

/// Embedded multi-color Google "G" logo widget.
class GoogleLogoIcon extends StatelessWidget {
  const GoogleLogoIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_googleLogoSvg, width: size, height: size);
  }
}

enum SocialProvider { google, apple, email }

/// Outlined, glassmorphic button for third-party sign-in options.
///
/// UI-only for now — [onPressed] is expected to be wired up once the
/// Google/Apple OAuth flows are implemented against Supabase.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.provider,
    required this.onPressed,
  });

  final SocialProvider provider;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (provider) {
      SocialProvider.google => l10n.continueWithGoogle,
      SocialProvider.apple => l10n.continueWithApple,
      SocialProvider.email => l10n.continueWithEmail,
    };

    final Widget icon = switch (provider) {
      SocialProvider.google => const GoogleLogoIcon(size: 20),
      SocialProvider.apple => const Icon(Icons.apple, size: 22, color: Colors.white),
      SocialProvider.email => Icon(Icons.email_outlined, size: 22, color: AppColors.universe.textStarlight),
    };

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.universe.glassWhiteLow,
          foregroundColor: AppColors.universe.textStarlight,
          side: BorderSide(color: AppColors.universe.glassBorder),
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// "── or ──" divider used to separate password auth from social auth.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textLabel = label ?? l10n.authOrDivider;
    final line = Expanded(
      child: Divider(color: AppColors.universe.glassBorder, thickness: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            textLabel,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
          ),
        ),
        line,
      ],
    );
  }
}
