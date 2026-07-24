// lib/presentation/pages/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// アカウント作成直後、一度だけ表示する初回設定画面。
/// Recording Language(オンデバイスASR/バックエンドWhisperの言語ヒント両方に
/// 使う)は必須。Realtime Recordingは任意だが、ここでONにしない限りモデルの
/// プロアクティブダウンロードは走らない。
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingLanguage = ref.watch(recordingLanguageControllerProvider);
    final realtimeEnabled = RecordingPreferences().getRealtimeTranscribe();
    final realtimeEnabledState = ValueNotifier<bool>(realtimeEnabled);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Set up your recording preferences',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'These settings can be changed later from your account page.',
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
              ),
              const SizedBox(height: 32),

              // Recording language(必須)
              Text(
                'Recording language',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const LanguageSelectionSheet(mode: LanguageSheetMode.recording),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.translate, color: AppColors.universe.textComet),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          recordingLanguageFromCode(recordingLanguage).englishName,
                          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.universe.textComet),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Realtime Recording(任意)
              ValueListenableBuilder<bool>(
                valueListenable: realtimeEnabledState,
                builder: (context, value, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.universe.glassWhiteLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.universe.glassBorder),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: value,
                      activeThumbColor: AppColors.starGold,
                      title: Text(
                        'Realtime transcribe',
                        style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Show live captions on-device while you record.',
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                      ),
                      onChanged: (val) async {
                        realtimeEnabledState.value = val;
                        await RecordingPreferences().setRealtimeTranscribe(val);
                        if (val) {
                          ref.read(asrModelManagerProvider.notifier).ensureModelReady(recordingLanguage);
                        }
                      },
                    ),
                  );
                },
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
                    if (context.mounted) context.go(AppRoutes.home);
                  },
                  child: const Text('Get started', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
