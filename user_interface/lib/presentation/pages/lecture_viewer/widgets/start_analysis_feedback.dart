// lib/presentation/pages/lecture_viewer/widgets/start_analysis_feedback.dart
//
// 「分析開始」(LectureController.startAnalysis)が失敗したときの見せ方を、
// 呼び出し元の画面どうしで揃えるための部品。
//
// startAnalysisはAsyncValue.guardで例外を握り、lectureControllerProviderの
// stateに入れるだけで投げ直さない。そのため呼び出し元はawaitの後にstateを
// 見ないと、失敗してもボタンのくるくるが止まるだけで何も表示されない
// (以前のProcessingView/PipelineProgressBannerの「最初からやり直す」がそうだった)。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/domain/exceptions/insufficient_credits_exception.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/snag_panel.dart';

/// クレジット不足/プラン未加入で分析を始められなかったときのダイアログ。
/// クレジットページへ誘導する。
void showInsufficientCreditsDialog(
  BuildContext context,
  AppLocalizations l10n,
  InsufficientCreditsException error,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        error.isNoAllocation
            ? l10n.notStartedNoActivePlanTitle
            : l10n.notStartedOutOfCreditsTitle,
      ),
      content: Text(
        error.isNoAllocation
            ? l10n.notStartedNoAllocationMessage
            : l10n.notStartedOutOfCreditsMessage,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.notStartedCancelButton),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(AppRoutes.creditDetail);
          },
          child: Text(l10n.notStartedViewCreditsButton),
        ),
      ],
    ),
  );
}

/// startAnalysisをawaitした直後に呼ぶ。失敗していればユーザーに見せる
/// (クレジット不足はダイアログ、それ以外はスナックバー)。
///
/// スナックバーの文言は[snagMessageFor]に任せる: 既知のコード(オフライン、
/// 音声未アップロード等)は専用の1文、未知のものは「こちらの不具合です+参照コード」
/// を出し、同時に開発者へ報告する。
void showStartAnalysisErrorIfAny(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n, {
  required String origin,
}) {
  if (!context.mounted) return;
  final error = ref.read(lectureControllerProvider).error;
  if (error == null) return;

  if (error is InsufficientCreditsException) {
    showInsufficientCreditsDialog(context, l10n, error);
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        snagMessageFor(
          l10n,
          error,
          origin: origin,
          actionName: l10n.processingViewStartOverFromScratchButton,
        ),
      ),
    ),
  );
}
