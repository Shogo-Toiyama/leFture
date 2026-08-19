import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

enum LanguageSheetMode { recording, display }

class LanguageSelectionSheet extends ConsumerWidget {
  const LanguageSelectionSheet({
    super.key,
    required this.mode,
  });

  final LanguageSheetMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isRecording = mode == LanguageSheetMode.recording;

    final currentCode = isRecording
        ? ref.watch(recordingLanguageControllerProvider)
        : ref.watch(displayLanguageControllerProvider);

    final languages = isRecording ? kRecordingLanguages : kDisplayLanguages;

    final title = isRecording
        ? l10n.onboardingLanguageRecordingLabel
        : l10n.onboardingLanguageDisplayLabel;
    final subtitle = isRecording
        ? l10n.onboardingLanguageRecordingDesc
        : l10n.onboardingLanguageDisplayDesc;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.voidBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ドラッグハンドル
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isRecording
                          ? Icons.record_voice_over_outlined
                          : Icons.language_rounded,
                      color: AppColors.starGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: AppColors.universe.glassBorder, height: 1),

            // 言語リスト
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: languages.length,
                separatorBuilder: (context, index) => Divider(
                  color: AppColors.universe.glassBorder,
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                ),
                itemBuilder: (context, index) {
                  final lang = languages[index];
                  final isSelected = lang.code == currentCode;

                  return _LanguageTile(
                    language: lang,
                    isSelected: isSelected,
                    onTap: () {
                      if (!isSelected) {
                        if (isRecording) {
                          unawaited(ref
                              .read(recordingControllerProvider.notifier)
                              .updateRecordingLanguage(lang.code));
                        } else {
                          unawaited(ref
                              .read(displayLanguageControllerProvider.notifier)
                              .setLanguage(lang.code));
                        }
                      }
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayLangCode = ref.watch(displayLanguageControllerProvider);
    final mainTitle = language.getNativeName(displayLangCode);
    final subTitle = language.localizedName(displayLangCode);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainTitle,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.starGold
                          : AppColors.universe.textStarlight,
                      fontSize: 16,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (subTitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subTitle,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: AppColors.starGold,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

