import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

enum PasswordStrength { empty, weak, fair, good, strong }

class PasswordRequirement {
  const PasswordRequirement(this.label, this.isMet);
  final String label;
  final bool isMet;
}

class PasswordStrengthResult {
  const PasswordStrengthResult(this.strength, this.requirements);
  final PasswordStrength strength;
  final List<PasswordRequirement> requirements;
}

PasswordStrengthResult evaluatePasswordStrength(String password) {
  final hasMinLength = password.length >= 8;
  final hasLongLength = password.length >= 12;
  final hasUpperAndLower = RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password);
  final hasDigit = RegExp(r'[0-9]').hasMatch(password);
  final hasSymbol = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]').hasMatch(password);

  final requirements = [
    PasswordRequirement('At least 8 characters', hasMinLength),
    PasswordRequirement('Upper & lowercase letters', hasUpperAndLower),
    PasswordRequirement('At least one number', hasDigit),
    PasswordRequirement('At least one symbol', hasSymbol),
  ];

  if (password.isEmpty) {
    return PasswordStrengthResult(PasswordStrength.empty, requirements);
  }

  var score = 0;
  if (hasMinLength) score++;
  if (hasLongLength) score++;
  if (hasUpperAndLower) score++;
  if (hasDigit) score++;
  if (hasSymbol) score++;
  if (!hasMinLength) score = score.clamp(0, 1);

  final strength = switch (score) {
    0 || 1 => PasswordStrength.weak,
    2 => PasswordStrength.fair,
    3 || 4 => PasswordStrength.good,
    _ => PasswordStrength.strong,
  };

  return PasswordStrengthResult(strength, requirements);
}

extension on PasswordStrength {
  String get label => switch (this) {
        PasswordStrength.empty => '',
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

  Color get color => switch (this) {
        PasswordStrength.empty => AppColors.universe.glassBorder,
        PasswordStrength.weak => AppColors.correctionRed,
        PasswordStrength.fair => AppColors.alertAmber,
        PasswordStrength.good => AppColors.starGold,
        PasswordStrength.strong => AppColors.growthGreen,
      };

  int get filledSegments => switch (this) {
        PasswordStrength.empty => 0,
        PasswordStrength.weak => 1,
        PasswordStrength.fair => 2,
        PasswordStrength.good => 3,
        PasswordStrength.strong => 4,
      };
}

/// Live password strength indicator: a segmented bar plus a checklist of
/// what's still missing. Wire it to the same [TextEditingController] used
/// by the password field so it updates as the user types.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final result = evaluatePasswordStrength(value.text);
        if (result.strength == PasswordStrength.empty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < result.strength.filledSegments
                              ? result.strength.color
                              : AppColors.universe.glassBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text(
                    result.strength.label,
                    style: TextStyle(
                      color: result.strength.color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final requirement in result.requirements)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          requirement.isMet ? Icons.check_circle : Icons.circle_outlined,
                          size: 14,
                          color: requirement.isMet ? AppColors.growthGreen : AppColors.universe.textComet,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          requirement.label,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
