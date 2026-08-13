// lib/presentation/pages/lecture_viewer/widgets/lecture_overlay_card.dart
//
// FullScreenRevealBlurが中央に置くカード。以前はLectureStatusScaffoldが
// 「講義の状態に応じて画面ごと別ルートに切り替える」役割を持っていたが、
// 今はLectureViewerPageの本体を常に描画し続ける設計になったため、この
// Widgetは「まだ何も生成物が出ていない間だけ」中央に浮かぶカードの中身を
// 選ぶだけの役割に縮小されている。
//
// 呼び出し元(_LectureViewerBody)は既にhasAnyReady==falseであることを
// 確認した上でこれを表示するので、ここではuiStateに応じたカードの
// 中身を選ぶことだけに専念する。

import 'package:flutter/material.dart';
import 'package:lefture/application/lecture/lecture_state_providers.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/lecture_viewer/views/not_started_view.dart';
import 'package:lefture/presentation/pages/lecture_viewer/views/processing_view.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class LectureOverlayCard extends StatelessWidget {
  const LectureOverlayCard({super.key, required this.lecture, required this.uiState});

  final Lecture lecture;
  final LectureUIState uiState;

  @override
  Widget build(BuildContext context) {
    switch (uiState) {
      case LectureUIState.notStarted:
        return NotStartedView(lecture: lecture);

      case LectureUIState.processing:
      case LectureUIState.failed:
        // 分析中/失敗どちらもProcessingView側でjob.statusを見て
        // 見た目(ヘッダー色・Start Overの出し方)を切り替える。
        return ProcessingView(lectureId: lecture.id);

      case LectureUIState.syncing:
        return _MiniStatusCard(
          icon: Icons.cloud_upload_outlined,
          title: AppLocalizations.of(context).statusScaffoldSyncingTitle,
          message: AppLocalizations.of(context).statusScaffoldSyncingMessage,
        );

      case LectureUIState.loading:
      case LectureUIState.complete:
        // completeはFINALIZE_JOB完了(=heroCollageブロックready)を意味するため、
        // 呼び出し元のhasAnyReady判定と矛盾するはずが無い。念のための安全策。
        return const SizedBox.shrink();
    }
  }
}

class _MiniStatusCard extends StatelessWidget {
  const _MiniStatusCard({required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.starGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.starGold.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 32, color: AppColors.starGold),
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
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
