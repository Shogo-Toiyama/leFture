import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/application/profile/display_language_controller.dart';
import 'package:lecture_companion_ui/application/recording/recording_controller.dart';
import 'package:lecture_companion_ui/application/recording/recording_language_controller.dart';
import 'package:lecture_companion_ui/core/services/recording_preferences.dart';
import 'package:lecture_companion_ui/domain/entities/app_language.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/asr_model_dialog_helpers.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';

enum LanguageSheetMode { recording, display }

class LanguageSelectionSheet extends ConsumerWidget {
  const LanguageSelectionSheet({
    super.key,
    required this.mode,
  });

  final LanguageSheetMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRecording = mode == LanguageSheetMode.recording;

    final currentCode = isRecording
        ? ref.watch(recordingLanguageControllerProvider)
        : ref.watch(displayLanguageControllerProvider);

    final languages = isRecording ? kRecordingLanguages : kDisplayLanguages;

    final title = isRecording ? 'Recording Language' : 'Display Language';
    final subtitle = isRecording
        ? 'Used for on-device transcription'
        : 'Sets the language of app text';

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
                  // watchで再描画をトリガーしつつ、実際の値はgroupKey解決込みの
                  // statusForLanguageから読む(ja/ko/yueのような共有モデルでも
                  // 正しく反映されるように)。
                  ref.watch(asrModelManagerProvider);
                  final modelState = isRecording
                      ? ref.read(asrModelManagerProvider.notifier).statusForLanguage(lang.code)
                      : null;

                  return _LanguageTile(
                    language: lang,
                    isSelected: isSelected,
                    modelState: modelState,
                    onDownloadTap: isRecording
                        ? () => ensureAsrModelWithErrorDialog(context, ref, lang.code)
                        : null,
                    onPauseTap: isRecording
                        ? () => ref.read(asrModelManagerProvider.notifier).pauseDownload(lang.code)
                        : null,
                    onResumeTap: isRecording
                        ? () => resumeAsrModelWithErrorDialog(context, ref, lang.code)
                        : null,
                    onTap: () async {
                      if (!isSelected) {
                        if (isRecording) {
                          await ref
                              .read(recordingLanguageControllerProvider.notifier)
                              .setLanguage(lang.code);
                          if (context.mounted) {
                            await _maybeDownloadForNewLanguage(context, ref, lang);
                          }
                        } else {
                          await ref
                              .read(displayLanguageControllerProvider.notifier)
                              .setLanguage(lang.code);
                        }
                      }
                      if (context.mounted) Navigator.of(context).pop();
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

/// 録音言語を変更した直後、Realtime Recordingが有効でその言語のモデルが
/// まだ無い場合に、ダウンロードするかどうかをユーザーに確認する。
/// 「ダウンロードしない」を選んだ場合はRealtime Recording自体をOFFにする
/// (モデルが無いままONにしていても意味が無いため)。Realtime自体が無効なら
/// 何もしない(無駄な自動ダウンロードを避ける)。
Future<void> _maybeDownloadForNewLanguage(
  BuildContext context,
  WidgetRef ref,
  AppLanguage lang,
) async {
  if (!RecordingPreferences().getRealtimeTranscribe()) return;

  final status = ref.read(asrModelManagerProvider.notifier).statusForLanguage(lang.code).status;
  // 既に準備済み/進行中なら何もしなくてよい。
  if (status == AsrModelStatus.ready ||
      status == AsrModelStatus.downloading ||
      status == AsrModelStatus.checking) {
    return;
  }

  final confirmed = await showCustomDialog(
    context: context,
    title: 'Speech model required',
    message:
        "Download the on-device speech model for ${lang.englishName}? If you skip, Realtime transcribe will be turned off.",
    confirmLabel: 'Download',
    cancelLabel: 'Turn off',
    icon: Icons.download_rounded,
  );

  if (confirmed == true) {
    if (context.mounted) {
      await ensureAsrModelWithErrorDialog(context, ref, lang.code);
    }
  } else {
    await ref.read(recordingControllerProvider.notifier).setRealtimeTranscribe(false);
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
    this.modelState,
    this.onDownloadTap,
    this.onPauseTap,
    this.onResumeTap,
  });

  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;
  final AsrLanguageModelState? modelState;
  // recordingモードのみ。failed/unknown状態でタップするとダウンロード/リトライ。
  final VoidCallback? onDownloadTap;
  final VoidCallback? onPauseTap;
  final VoidCallback? onResumeTap;

  Widget? _buildStatusIndicator() {
    final status = modelState?.status;
    if (status == null) return null;
    switch (status) {
      case AsrModelStatus.checking:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.universe.textComet),
        );
      case AsrModelStatus.downloading:
        final progress = modelState?.progress;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    color: AppColors.starGold,
                  ),
                  if (progress != null)
                    Text(
                      '${(progress * 100).round()}',
                      style: TextStyle(fontSize: 6, color: AppColors.universe.textComet),
                    ),
                ],
              ),
            ),
            if (onPauseTap != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPauseTap,
                child: Icon(Icons.pause_circle_outline, color: AppColors.universe.textComet, size: 18),
              ),
            ],
          ],
        );
      case AsrModelStatus.paused:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onResumeTap,
          child: Icon(Icons.play_circle_outline, color: AppColors.starGold, size: 20),
        );
      case AsrModelStatus.ready:
        return const Icon(Icons.check_circle, color: AppColors.growthGreen, size: 16);
      case AsrModelStatus.failed:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDownloadTap,
          child: const Icon(Icons.download_rounded, color: AppColors.correctionRed, size: 18),
        );
      case AsrModelStatus.unknown:
        if (onDownloadTap == null) return null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDownloadTap,
          child: Icon(Icons.download_rounded, color: AppColors.universe.textComet, size: 18),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusIndicator = _buildStatusIndicator();

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
                    language.nativeName,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.starGold
                          : AppColors.universe.textStarlight,
                      fontSize: 16,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    language.englishName,
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (statusIndicator != null) ...[
              statusIndicator,
              const SizedBox(width: 10),
            ],
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
