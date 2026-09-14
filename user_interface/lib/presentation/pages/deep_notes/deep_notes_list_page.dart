// lib/presentation/pages/deep_notes/deep_notes_list_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/annotation.dart';
import 'package:lefture/domain/entities/deep_note.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/plan_features.dart' as plan_features;
import 'package:lefture/presentation/pages/profile/widgets/plan_theme.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/blurred_summary_placeholder.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/presentation/widgets/upgrade_required_dialog.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';


// ---------------------------------------------------------------------------
// Private data class (mirrors old _NoteTopic)
// ---------------------------------------------------------------------------
class DeepNoteTopic {
  const DeepNoteTopic({
    required this.index,
    required this.title,
    required this.summary,
    required this.content,
    this.noteId,
    this.reaction,
    this.saved = false,
    this.annotations = const [],
    this.imagePath,
  });

  final int index;
  final String title;
  final String summary;
  final String content;
  // 対応するDeepNote.id。ノートがまだ生成されていない場合はnull。
  final String? noteId;
  // "like" / "dislike" / null
  final String? reaction;
  final bool saved;
  final List<Annotation> annotations;
  final String? imagePath;
}

// ---------------------------------------------------------------------------
// List Page
// ---------------------------------------------------------------------------
class DeepNotesListPage extends HookConsumerWidget {
  const DeepNotesListPage({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final lecture = lectureAsync.asData?.value;
    final courseId = lecture?.courseId ?? 'N/A';

    final isTutorial = lecture?.metadata?['is_tutorial'] == true;

    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final notesAsync  = ref.watch(deepNotesProvider(lectureId));
    // Freeプランでは最初のトピックだけプレビュー生成され、2件目以降は
    // バックエンド側でそもそもdeep_notesが作られない(空文字のnote_contents)。
    // それを常時表示のロック付きカードとして見せる(タップ→アップグレード導線)。
    // ただしチュートリアル講義の場合は全トピックのノートが生成されているため常に解放する。
    final hasPlanFullDeepNotes = ref.watch(hasFeatureProvider(plan_features.featureDeepNotesFull));
    final hasFullDeepNotes = isTutorial || hasPlanFullDeepNotes;
    final showTutorialNotice = isTutorial && !hasPlanFullDeepNotes;

    final topics = useMemoized(() {
      final rawTopics = topicsAsync.asData?.value ?? <LectureTopic>[];
      final notes     = notesAsync.asData?.value  ?? <DeepNote>[];
      final noteMap   = {for (final n in notes) n.topicNumber: n};

      return rawTopics.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        final note = noteMap[t.index];
        return DeepNoteTopic(
          index: i,
          title: t.displayTitle,
          summary: t.summary ?? '',
          content: note?.noteContents ?? '',
          noteId: note?.id,
          reaction: note?.reaction,
          saved: note?.saved ?? false,
          annotations: note?.annotations ?? const [],
        );
      }).toList();
    }, [topicsAsync, notesAsync]);

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: SafeArea(
        child: Column(
          children: [
            CustomAppBar(
              showHomeButton: true,
              title: l10n.deepNotesListTitle,
              isLightBg: true,
            ),
            Expanded(
              child: _buildBody(
                context,
                topics,
                notesAsync.isLoading || topicsAsync.isLoading,
                courseId,
                hasFullDeepNotes,
                showTutorialNotice,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<DeepNoteTopic> topics,
    bool isLoading,
    String courseId,
    bool hasFullDeepNotes,
    bool showTutorialNotice,
  ) {
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold));
    }

    if (topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: AppColors.paper.textPencil),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).deepNotesListGeneratingMessage,
              style:
                  TextStyle(color: AppColors.paper.textPencil, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: topics.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final l10n = AppLocalizations.of(context);
        final topic = topics[index];
        final hasContent = topic.content.trim().isNotEmpty;
        // Freeプランでは最初のトピック(index==0)だけがプレビューとして実際に
        // 生成される。2件目以降は(まだ処理中なのではなく)そもそもプランで
        // 絞られているため、hourglass(処理中)ではなくlock(要アップグレード)
        // 扱いにする。
        final isLocked = index > 0 && !hasFullDeepNotes;
        final lockColor = planThemeColor(plan_features.tierLite);

        return GestureDetector(
          onTap: isLocked
              ? () => showUpgradeRequiredDialog(
                    context: context,
                    requiredTierColor: lockColor,
                    title: AppLocalizations.of(context).deepNotesLockedDialogTitle,
                    message: AppLocalizations.of(context).deepNotesLockedDialogMessage,
                    viewPlansLabel: AppLocalizations.of(context).upgradeRequiredViewPlansButton,
                    cancelLabel: AppLocalizations.of(context).recordingCancelButton,
                  )
              : () => context.push(
                  '${AppRoutes.coursesRootPath}/c/$courseId/dnd/$lectureId/${topic.index}',
                  extra: topics),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.paper.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isLocked
                      ? lockColor.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Index badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isLocked ? lockColor : AppColors.deepGold)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isLocked ? lockColor : AppColors.deepGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTutorialNotice && index > 0) ...[
                        Text(
                          l10n.deepNotesTutorialNotice,
                          style: TextStyle(
                            color: lockColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        topic.title,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (isLocked) ...[
                        BlurredSummaryPlaceholder(color: lockColor),
                        const SizedBox(height: 4),
                        // ブラー単体だと「本当は存在していて隠されているだけ」に
                        // 見えかねないため、一目で「生成されていない」と分かる
                        // キャプションを添える(ダイアログを開かなくても伝わるように)。
                        Text(
                          AppLocalizations.of(context).deepNotesLockedCaption,
                          style: TextStyle(
                            color: lockColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (topic.summary.isNotEmpty)
                        Text(
                          topic.summary,
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  isLocked
                      ? Icons.lock_outline_rounded
                      : (hasContent
                          ? Icons.chevron_right
                          : Icons.hourglass_empty_outlined),
                  color: isLocked
                      ? lockColor
                      : (hasContent
                          ? AppColors.deepGold
                          : AppColors.paper.textPencil),
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
