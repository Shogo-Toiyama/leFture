import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.buttonIcon,
    this.buttonLabel,
    this.onButtonPressed,
    this.isError = false,
    this.isLoading = false, // ★ 追加: ローディング中かどうか
  });

  final IconData icon;
  final String title;
  final String? message;
  final IconData? buttonIcon;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;
  final bool isError;
  final bool isLoading; // ★ 追加

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.correctionRed : AppColors.starGold;

    return Container(
      color: AppColors.universe.voidBackground,
      child: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, size: 40, color: color),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                  ),
                ],
                if (onButtonPressed != null) ...[
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: isLoading ? null : onButtonPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: color.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(buttonIcon),
                    label: Text(isLoading ? 'Processing...' : buttonLabel!),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
