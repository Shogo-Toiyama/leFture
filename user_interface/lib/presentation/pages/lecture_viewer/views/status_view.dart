import 'package:flutter/material.dart';

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
    final color = isError 
        ? Theme.of(context).colorScheme.error 
        : Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: isError ? color : Colors.grey),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isError ? color : null,
                      fontWeight: FontWeight.bold,
                    ),
              ),

              if (onButtonPressed != null) ...[
                const SizedBox(height: 32),
                
                isError
                    ? OutlinedButton.icon(
                        onPressed: isLoading ? null : onButtonPressed,
                        icon: isLoading
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                            : Icon(buttonIcon),
                        label: Text(isLoading ? 'Processing...' : buttonLabel!),
                        style: OutlinedButton.styleFrom(foregroundColor: color),
                      )
                    : TextButton.icon(
                        onPressed: isLoading ? null : onButtonPressed,
                        icon: isLoading
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                            : Icon(buttonIcon),
                        label: Text(isLoading ? 'Processing...' : buttonLabel!),
                        style: TextButton.styleFrom(foregroundColor: color),
                      ),
              ],
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}