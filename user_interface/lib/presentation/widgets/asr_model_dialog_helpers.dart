// lib/presentation/widgets/asr_model_dialog_helpers.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/presentation/widgets/app_error_dialog.dart';

/// 明示的なユーザー操作(ダウンロード/リトライ/再開ボタンのタップなど)から
/// [AsrModelManager.ensureModelReady]を呼び、失敗した場合は[AppErrorDialog]で
/// エラーを表示する共通ヘルパー。バックグラウンド/自動トリガーからは
/// 呼ばない(黙って失敗状態のアイコンに落ち着かせるのが仕様のため)。
Future<void> ensureAsrModelWithErrorDialog(
  BuildContext context,
  WidgetRef ref,
  String languageCode,
) async {
  await ref.read(asrModelManagerProvider.notifier).ensureModelReady(languageCode);
  final result = ref.read(asrModelManagerProvider.notifier).statusForLanguage(languageCode);
  if (result.status == AsrModelStatus.failed && context.mounted) {
    AppErrorDialog.show(
      context,
      actionName: 'downloading the speech model',
      rawError: result.errorMessage ?? 'Unknown error',
    );
  }
}

/// 一時停止中のダウンロードを再開する明示的な操作から呼ぶ。失敗時の扱いは
/// [ensureAsrModelWithErrorDialog]と同じ。
Future<void> resumeAsrModelWithErrorDialog(
  BuildContext context,
  WidgetRef ref,
  String languageCode,
) async {
  await ref.read(asrModelManagerProvider.notifier).resumeDownload(languageCode);
  final result = ref.read(asrModelManagerProvider.notifier).statusForLanguage(languageCode);
  if (result.status == AsrModelStatus.failed && context.mounted) {
    AppErrorDialog.show(
      context,
      actionName: 'downloading the speech model',
      rawError: result.errorMessage ?? 'Unknown error',
    );
  }
}

/// [_RecordingLanguageRow]等でユーザーに見せる、失敗時のユーザーフレンドリーな
/// 一言メッセージ。生の例外文言(スタックトレース由来の技術的な文字列)は
/// [AppErrorDialog]の「Technical Details」でのみ見せ、常時表示するインライン
/// テキストはここで固定文言に丸める。
const String friendlyAsrModelErrorMessage =
    "Couldn't prepare the speech model. Tap to retry.";
