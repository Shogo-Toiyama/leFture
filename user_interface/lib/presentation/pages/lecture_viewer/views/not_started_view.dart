import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/domain/exceptions/insufficient_credits_exception.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class NotStartedView extends HookConsumerWidget {
  const NotStartedView({super.key, required this.lecture});

  final Lecture lecture;

  void _showInsufficientCreditsDialog(
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

  /// UploadManagerの自動発火経路は、失敗の詳細をDB(LocalUploadJobs.lastError)に
  /// 文字列として保存するため、型情報が失われる。InsufficientCreditsException.
  /// toString()の形式("InsufficientCreditsException(ERROR_CODE): message")を
  /// 手掛かりに復元する。
  InsufficientCreditsException? _parseInsufficientCreditsError(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^InsufficientCreditsException\(([^)]+)\): (.*)$', dotAll: true)
        .firstMatch(raw);
    if (match == null) return null;
    return InsufficientCreditsException(
      errorCode: match.group(1)!,
      message: match.group(2) ?? '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // クレジット不足/未加入エラーは、汎用のインラインエラー表示ではなく
    // 専用ダイアログでクレジットページへ誘導する。ref.listenなのでstateが
    // 変化した瞬間だけ発火し、rebuildのたびに再表示することはない。
    ref.listen<AsyncValue<void>>(lectureControllerProvider, (previous, next) {
      final error = next.error;
      if (error is InsufficientCreditsException) {
        _showInsufficientCreditsDialog(context, l10n, error);
      }
    });

    // アップロード完了後の自動発火(start_analysisジョブ)がクレジット不足で
    // 失敗した場合も、手動ボタンと同じダイアログを出す。こちらは型情報を
    // 保っていないので、lastErrorの文字列から復元して判定する。新しく
    // クレジット不足エラーになった瞬間だけ発火させる(既にクレジット不足の
    // 状態が続いているだけの再評価では毎回再表示しないよう、直前の状態と
    // 比較する)。
    ref.listen<AsyncValue<List<LocalUploadJob>>>(startAnalysisJobsProvider(lecture.id), (
      previous,
      next,
    ) {
      final prevError = _parseInsufficientCreditsError(
        previous?.value?.map((j) => j.lastError).firstWhere((e) => e != null, orElse: () => null),
      );
      final nextError = _parseInsufficientCreditsError(
        next.value?.map((j) => j.lastError).firstWhere((e) => e != null, orElse: () => null),
      );
      if (nextError != null && prevError == null) {
        _showInsufficientCreditsDialog(context, l10n, nextError);
      }
    });

    final controllerState = ref.watch(lectureControllerProvider);
    final isLoading = controllerState.isLoading;
    final hasCourse = lecture.courseId != null;
    final creditError = controllerState.error;
    final showInlineError = controllerState.hasError && creditError is! InsufficientCreditsException;

    // アップロード完了後の自動分析開始(start_analysisジョブ)が既に1回以上失敗して
    // バックグラウンドでリトライ待ちになっている場合、無言で失敗させず可視化する。
    // ただしクレジット不足は上のref.listenで専用ダイアログを出すので、生の
    // JSONエラー文字列をそのまま出す汎用バナーには含めない。
    final startAnalysisJobs = ref.watch(startAnalysisJobsProvider(lecture.id)).value ?? const [];
    final autoStartErrorRaw = startAnalysisJobs
        .map((j) => j.lastError)
        .firstWhere((e) => e != null, orElse: () => null);
    final autoStartError =
        _parseInsufficientCreditsError(autoStartErrorRaw) == null ? autoStartErrorRaw : null;

    // ★ 「分析開始の号砲(start_analysisジョブ)は既にローカルで鳴らしてある」場合、
    // Start Analysisボタンを再び出してはいけない。lectureStateProvider(3秒
    // ポーリング)がサーバー側のjob作成を検知するまでの数秒間、job==nullの
    // ままnotStartedに落ちてこの画面が再描画されてしまうため
    // (「アップロード完了後も数秒Start Analysisボタンが出続ける」というちらつき
    // の原因だった)。'done'も含めて見る(既に発火成功していても同じ理由で
    // 再表示を防ぎたいため)。
    final isAnalysisStarting =
        (ref.watch(startAnalysisJobsIncludingDoneProvider(lecture.id)).value ?? const []).isNotEmpty;

    // ★ 音声のアップロードが終わるまでStart Analysisを押させない。
    // 電波が弱い場所ではチャンク/マスター音声がリトライ待ちのまま残るが、この
    // 画面自体は「Ready to Analyze」を表示してしまうため、ユーザーが押せると
    // audio_path未設定のままTRANSCRIBE_MASTERが走り、「音声ファイルがありません」で
    // ジョブごと失敗する。アップロードが完了すれば自動発火するので、ここでは
    // 待たせるのが正しい。
    final pendingUploadJobs =
        ref.watch(pendingAudioUploadJobsProvider(lecture.id)).value ?? const [];
    final isUploading = pendingUploadJobs.isNotEmpty;
    final uploadRetryError = pendingUploadJobs
        .map((j) => j.lastError)
        .firstWhere((e) => e != null, orElse: () => null);

    // ユーザーが「アップロードを止める」を押した講義。ファイルは端末に残った
    // ままなので、いつでも[resumeUpload]で再開できる。
    final cancelledUploadJobs =
        ref.watch(cancelledAudioUploadJobsProvider(lecture.id)).value ?? const [];
    final isUploadCancelled = !isUploading && cancelledUploadJobs.isNotEmpty;

    // Cancel/Resumeボタン専用のローディング状態。lectureControllerProviderの
    // 共有状態(isLoading)を使うと、Start Analysisボタンの「開始しています...」
    // 表示と誤って連動してしまうため、ここだけ独立させる。
    final isCancellingUpload = useState(false);
    final isResumingUpload = useState(false);

    Future<void> cancelUpload() async {
      isCancellingUpload.value = true;
      try {
        await ref.read(lectureControllerProvider.notifier).cancelUpload(lecture.id);
      } finally {
        isCancellingUpload.value = false;
      }
    }

    Future<void> resumeUpload() async {
      isResumingUpload.value = true;
      try {
        await ref.read(lectureControllerProvider.notifier).resumeUpload(lecture.id);
      } finally {
        isResumingUpload.value = false;
      }
    }

    Future<void> assignCourse() async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LectureEditSheet(lecture: lecture),
      );
    }

    if (isAnalysisStarting) {
      return _StartingCard(title: l10n.notStartedAnalysisStartingTitle, subtitle: l10n.notStartedAnalysisStartingSubtitle);
    }

    // ★ このWidgetはもはや専用の全画面ルートではなく、LectureOverlayCardが
    // FullScreenRevealBlurの中央に置くコンパクトなカードの中身として使われる。
    // 背景のブラー自体は呼び出し元(_LectureViewerBody)が担うので、ここでは
    // カード自身の見た目(角丸・半透明背景・影)だけを持てば良い。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.universe.voidBackground.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.universe.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.starGold.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.auto_awesome, size: 40, color: AppColors.starGold),
              ),
              const SizedBox(height: 28),
              Text(
                l10n.notStartedReadyTitle,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.notStartedReadySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
              ),
              const SizedBox(height: 8),
              // コースが既に設定済みの場合、以前はタイトル・コースを編集する
              // 導線がこの画面に無かった(下の警告バナーは!hasCourseの時しか
              // 出ないため)。LectureEditSheet自体はどちらの用途にも対応
              // しているので、常時使えるボタンとして出す。
              TextButton.icon(
                onPressed: assignCourse,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l10n.notStartedEditTooltip),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.universe.textComet,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!hasCourse) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.alertAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.alertAmber.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.alertAmber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.notStartedNoCourseWarning,
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: assignCourse,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.alertAmber,
                            side: BorderSide(color: AppColors.alertAmber.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: Text(l10n.notStartedChooseCourseButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isUploading) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.starGold.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.starGold,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              uploadRetryError == null
                                  ? l10n.notStartedUploadingWarning
                                  : l10n.notStartedUploadRetryingWarning(uploadRetryError),
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isCancellingUpload.value ? null : cancelUpload,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.universe.textComet,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: isCancellingUpload.value
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.universe.textComet,
                                  ),
                                )
                              : Text(l10n.notStartedCancelUploadButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isUploadCancelled) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle_outline, color: AppColors.universe.textComet, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.notStartedUploadStoppedWarning,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: isResumingUpload.value ? null : resumeUpload,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.starGold,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: isResumingUpload.value
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.starGold),
                              )
                            : const Icon(Icons.play_arrow, size: 16),
                        label: Text(l10n.notStartedResumeUploadButton),
                      ),
                    ],
                  ),
                ),
              ],
              if (autoStartError != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.correctionRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.correctionRed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.notStartedAutoStartFailedWarning(autoStartError),
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: (isLoading || !hasCourse || isUploading || isUploadCancelled)
                    ? null
                    : () {
                        ref.read(lectureControllerProvider.notifier).startAnalysis(lecture.id);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.starGold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                  disabledForegroundColor: AppColors.universe.textComet,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  isLoading
                      ? l10n.notStartedStartingLabel
                      : isUploading
                          ? l10n.notStartedUploadingLabel
                          : isUploadCancelled
                              ? l10n.notStartedUploadStoppedLabel
                              : l10n.notStartedStartAnalysisButton,
                ),
              ),
              if (showInlineError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    l10n.notStartedErrorPrefix(controllerState.error.toString()),
                    style: const TextStyle(color: AppColors.correctionRed),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// アップロード完了直後、サーバーが分析ジョブを作るまでの数秒間だけ挟む
/// つなぎのカード。Start Analysisボタンを一瞬だけ再表示してしまう
/// (=NotStartedView.buildの冒頭を参照)のを防ぐためのもの。
class _StartingCard extends StatelessWidget {
  const _StartingCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.universe.voidBackground.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.universe.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.starGold),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
