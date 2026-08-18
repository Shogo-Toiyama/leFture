import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/core/utils/sid_citation.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_content_recovery.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/domain/entities/fun_fact.dart';
import 'package:lefture/domain/entities/keyword.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcements_sheet.dart';
import 'package:lefture/presentation/widgets/glowing_rainbow_border.dart';
import 'package:lefture/app/navigation_utils.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/keyword_repository_drift.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/application/lecture/lecture_state_providers.dart';
import 'package:lefture/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/lecture_hero_collage.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/lecture_viewer/pipeline_reveal_sync.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/lecture_overlay_card.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/presentation/pages/home/widgets/tutorial_lecture_callout.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/pipeline_progress_banner.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/reveal.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/topics_sheet.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';

class LectureViewerPage extends HookConsumerWidget {
  const LectureViewerPage({
    super.key,
    required this.lectureId,
    this.initialOpenAnnouncementId,
    this.initialScrollTo,
  });

  final String lectureId;
  final String? initialOpenAnnouncementId;
  final String? initialScrollTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDummy = lectureId.startsWith('dummy_');

    // 講義詳細を開いたタイミングでlastAccessedAtを更新する(キャッシュ容量管理の
    // LRU判定用)。lectureIdが変わった時だけ実行し、再ビルドの度には走らない。
    useEffect(() {
      if (!isDummy) {
        final db = ref.read(appDatabaseProvider);
        db.touchLectureAccessed(lectureId);
        // ローカルキャッシュの容量上限([LocalRetentionService])でこの講義の
        // Review Card/Deep Note/Fun Fact/Keyword/Topicが既に削除されていた
        // 場合、Supabaseから再取得してローカルDBへ復元する(トピックが
        // 1件でも既にあれば何もしない)。復元されたStream経由のプロバイダが
        // 自動的にUIへ反映される。
        unawaited(ensureLectureContentAvailable(db, lectureId));
      }
      return null;
    }, [lectureId]);

    if (isDummy) {
      final dummyLecture = Lecture(
        id: lectureId,
        userId: 'dummy_user',
        courseId: 'dummy_course',
        title: 'Introduction to OOP & Classes',
        sortOrder: 0,
        lectureDatetime: DateTime.now().subtract(const Duration(days: 2)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      return Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        // dummyデータには実際のprocessing_jobsが存在しないため、reveal機構を
        // 素通りさせて常にcomplete相当(完成品プレビュー)を描画させる。
        body: _LectureViewerBody(lecture: dummyLecture, uiState: LectureUIState.complete),
      );
    }

    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final initialLecture = lectureAsync.asData?.value;
    final courseId = initialLecture?.courseId;

    final lecturesAsync = courseId != null
        ? ref.watch(lectureListStreamProvider(courseId))
        : const AsyncValue<List<Lecture>>.loading();

    return lectureAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.starGold),
        ),
      ),
      error: (err, stack) => Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: Center(
          child: Text(
            l10n.lectureViewerErrorPrefix(err.toString()),
            style: const TextStyle(color: AppColors.correctionRed),
          ),
        ),
      ),
      data: (lecture) {
        if (lecture == null) {
          return Scaffold(
            backgroundColor: AppColors.universe.voidBackground,
            body: Center(
              child: Text(
                l10n.lectureViewerLectureNotFound,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return lecturesAsync.when(
          loading: () => Scaffold(
            backgroundColor: AppColors.universe.voidBackground,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.starGold),
            ),
          ),
          error: (err, stack) => Scaffold(
            backgroundColor: AppColors.universe.voidBackground,
            body: Center(
              child: Text(
                l10n.lectureViewerErrorPrefix(err.toString()),
                style: const TextStyle(color: AppColors.correctionRed),
              ),
            ),
          ),
          data: (lectures) {
            // Sort ascending (chronological: oldest first, newer to the right)
            final sortedLectures = [...lectures]
              ..sort((a, b) => a.lectureDatetime.compareTo(b.lectureDatetime));

            final initialIndex = sortedLectures.indexWhere(
              (l) => l.id == lecture.id,
            );

            if (initialIndex == -1) {
              // Fallback if current lecture is not found in the list (e.g. database syncing)
              return Scaffold(
                backgroundColor: AppColors.universe.voidBackground,
                body: _LecturePageContent(lecture: lecture),
              );
            }

            final pageController = usePageController(initialPage: initialIndex);

            return Scaffold(
              backgroundColor: AppColors.universe.voidBackground,
              body: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollEndNotification) {
                    final page = pageController.page?.round();
                    if (page != null &&
                        page >= 0 &&
                        page < sortedLectures.length) {
                      final targetLecture = sortedLectures[page];
                      if (targetLecture.id != lectureId) {
                        context.replace(
                          '${AppRoutes.coursesRootPath}/c/${targetLecture.courseId}/v/${targetLecture.id}',
                        );
                      }
                    }
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: pageController,
                  itemCount: sortedLectures.length,
                  itemBuilder: (context, index) {
                    final lectureItem = sortedLectures[index];
                    return _LecturePageContent(
                      lecture: lectureItem,
                      initialOpenAnnouncementId: lectureItem.id == lectureId ? initialOpenAnnouncementId : null,
                      initialScrollTo: lectureItem.id == lectureId ? initialScrollTo : null,
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LecturePageContent extends ConsumerWidget {
  const _LecturePageContent({
    required this.lecture,
    this.initialOpenAnnouncementId,
    this.initialScrollTo,
  });

  final Lecture lecture;
  final String? initialOpenAnnouncementId;
  final String? initialScrollTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uiStateAsync = ref.watch(lectureStateProvider(lecture.id));

    ref.listen<AsyncValue<LectureUIState>>(lectureStateProvider(lecture.id), (
      previous,
      next,
    ) {
      // 「completeである間ずっと」ではなく「completeに“なった瞬間”」だけ拾う。
      // lectureStateProviderはjob状態だけでなくローカル講義行の更新でも
      // 再評価されうるため、previousとの比較なしだとcomplete判定のたびに
      // bootstrapLectures()が無限に呼ばれるループになっていた
      // (bootstrapLecturesのPullがローカル講義行を書き換え→再評価→再度complete
      // 判定→bootstrapLectures…という自己増殖ループ)。
      final wasAlreadyComplete = previous?.value == LectureUIState.complete;
      next.whenData((state) {
        if (state == LectureUIState.complete && !wasAlreadyComplete) {
          final uid = supabase.auth.currentUser?.id;
          if (uid != null) {
            ref.invalidate(transcriptProvider(uid: uid, lectureId: lecture.id));
          }
          ref
              .read(lectureControllerProvider.notifier)
              .bootstrapLectures(reason: 'lecture_viewer_became_complete');
        }
      });
    });

    return uiStateAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.starGold),
      ),
      error: (err, stack) => Center(
        child: Text(
          l10n.lectureViewerErrorPrefix(err.toString()),
          style: const TextStyle(color: AppColors.correctionRed),
        ),
      ),
      // ★ 以前はuiState=='complete'の時だけ_LectureViewerBodyを描画し、それ
      // 以外(notStarted/processing/failed)は全く別画面(LectureStatusScaffold)
      // へ丸ごと切り替えていた。今はどのuiStateでも常に_LectureViewerBodyを
      // 描画する —— 本体側が要素ごとの完成度(RevealState)とjob/tasksを見て、
      // スケルトン/ブラー/バナーを自分で出し分ける設計に変わったため。
      data: (uiState) => _LectureViewerBody(
        lecture: lecture,
        uiState: uiState,
        initialOpenAnnouncementId: initialOpenAnnouncementId,
        initialScrollTo: initialScrollTo,
      ),
    );
  }
}

class _LectureViewerBody extends HookConsumerWidget {
  const _LectureViewerBody({
    required this.lecture,
    required this.uiState,
    this.initialOpenAnnouncementId,
    this.initialScrollTo,
  });

  final Lecture lecture;

  /// 講義全体の粗いステータス(lectureStateProvider由来)。何も生成物が
  /// まだ無い間([FullScreenRevealBlur]が有効な間)の中央カードの中身選びに
  /// 使う。complete固定で渡された場合(dummyデータのプレビュー用)は、
  /// 個々のブロックのreveal判定を全てreadyへ強制する。
  final LectureUIState uiState;
  final String? initialOpenAnnouncementId;
  final String? initialScrollTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final topics =
        ref.watch(lectureTopicsProvider(lecture.id)).asData?.value ??
        const <LectureTopic>[];
    final keywords =
        ref.watch(lectureKeywordsProvider(lecture.id)).asData?.value ??
        const <Keyword>[];
    final funFacts =
        ref.watch(funFactsForLectureProvider(lecture.id)).asData?.value ??
        const <FunFact>[];
    final announcements =
        ref.watch(announcementsForLectureProvider(lecture.id)).asData?.value ??
        const <Announcement>[];

    final courses =
        ref.watch(courseListProvider).asData?.value ?? const <Course>[];
    final course = courses.cast<Course?>().firstWhere(
      (c) => c?.id == lecture.courseId,
      orElse: () => null,
    );

    final displayTitle = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true
              ? lecture.titleGenerated!
              : l10n.lectureViewerUntitledLecture);
    final summary = lecture.summary == null
        ? null
        : stripSidCitations(lecture.summary!).trim();
    final themeColor = CourseStyleHelper.hexToColor(
      course?.color,
      fallback: AppColors.starGold,
    );

    final userProfile = ref.watch(currentUserProfileProvider).asData?.value;
    final isTutorialCompleted = userProfile?.metadata?['tutorial_completed_at'] != null;
    final isTutorial = lecture.metadata?['is_tutorial'] == true;
    final showReviewCardsTutorialCallout = isTutorial && !isTutorialCompleted;

    // --- 「完成した要素から出していく」演出のための状態計算 -----------------
    //
    // uiState==completeで呼ばれた場合(dummyプレビュー、または実際に分析が
    // 完了した講義)は、job/tasksの実態に関わらず全ブロックをreadyへ強制する。
    // dummyレクチャーにはprocessing_jobs行が存在しないため、これが無いと
    // プレビューが永久にスケルトンのまま止まってしまう。
    final forceReady = uiState == LectureUIState.complete;

    final job = ref.watch(jobStreamProvider(lecture.id)).asData?.value;
    final tasks = job == null
        ? const <ProcessingTask>[]
        : ref.watch(jobTasksStreamProvider(job.id)).asData?.value ?? const <ProcessingTask>[];
    final tasksByType = {for (final t in tasks) t.taskType: t};
    // ERRORは旧pipeline.py(JobStatus.ERROR)が書く失敗ステータス。FAILEDと同じく
    // 「もう自力では進まない」終端として扱う(processing_view.dartと同じ判定)。
    final jobFailed = job?.status == 'FAILED' || job?.status == 'ERROR';

    // タスクがCOMPLETEDになったのを検知するたびに、対応するテーブルだけを
    // 差分Pullする。フック呼び出しは必ずbuildの毎回・分岐前に行うこと
    // (Hooksのルール上、呼び出し回数や順序を条件分岐で変えてはいけないため)。
    usePipelineRevealSync(ref: ref, lectureId: lecture.id, tasks: tasks);

    ElementReveal reveal(List<String> taskTypes) => forceReady
        ? const ElementReveal(RevealState.ready)
        : computeReveal(taskTypes: taskTypes, tasksByType: tasksByType, jobFailed: jobFailed);

    final transcriptReveal = reveal(const ['TRANSCRIBE_MASTER', 'CHECK_AND_ASSEMBLE']);
    final summaryReveal = reveal(const ['CORE_EXTRACTION']);
    final keywordsReveal = reveal(const ['CORE_EXTRACTION']);
    final announcementsReveal = reveal(const ['ANNOUNCEMENT_GENERATION']);
    final topicsReveal = reveal(const ['DETAIL_CONTENTS_GENERATION']);
    final reviewCardsReveal = reveal(const ['REVIEW_CARD_GENERATION']);
    final deepNotesReveal = reveal(const ['DETAIL_CONTENTS_GENERATION']);
    final funFactReveal = reveal(const ['FUN_FACTS_GENERATION']);
    // Hero Collageの画像パスはFINALIZE_JOB(パイプライン最後の集計タスク)で
    // 一括してlecture_topicsへ書き込まれるため、他のブロックのように途中で
    // 段階的に出すことができない仕様。演出上は「最後に登場する要素」として
    // 割り切る。
    final heroCollageReveal = reveal(const ['FINALIZE_JOB']);

    final hasAnyReady = [
      transcriptReveal,
      summaryReveal,
      announcementsReveal,
      topicsReveal,
      reviewCardsReveal,
      deepNotesReveal,
      funFactReveal,
      heroCollageReveal,
    ].any((r) => r.isReady);

    final funFactKey = useMemoized(() => GlobalKey());
    final hasScrolledToFunFact = useRef(false);
    final hasOpenedAnnouncement = useRef(false);

    useEffect(() {
      if (initialScrollTo == 'fun_fact' && !hasScrolledToFunFact.value && funFacts.isNotEmpty) {
        hasScrolledToFunFact.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = funFactKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              alignment: 0.1,
            );
          }
        });
      }
      return null;
    }, [initialScrollTo, funFacts]);

    useEffect(() {
      if (initialOpenAnnouncementId != null && !hasOpenedAnnouncement.value && announcements.isNotEmpty) {
        hasOpenedAnnouncement.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showAnnouncementsSheet(
            context,
            lecture.id,
            announcements,
            targetAnnouncementId: initialOpenAnnouncementId,
          );
        });
      }
      return null;
    }, [initialOpenAnnouncementId, announcements]);

    // 何かは既に出ているが、ジョブ自体はまだ完了していない(生成中 or 一部失敗)
    // 間だけ、控えめな進捗/エラーバナーを出す。全部readyになった(=complete)
    // 瞬間に自然に消える。
    final showProgressBanner = !forceReady && hasAnyReady && job != null && job.status != 'COMPLETED';

    // ★ ヘッダー(プロフィールアイコン・Homeボタン)はブラーの対象外にする。
    // FullScreenRevealBlurはchildに渡したもの全部にブラー+暗いオーバーレイを
    // かけるため、CustomAppBarをその外側(常にシャープ・常に操作可能)に出し、
    // ブラーの対象は「進捗バナー + スクロール本体」だけに絞る。
    final blurredBody = Column(
      children: [
            if (showProgressBanner)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: PipelineProgressBanner(
                  lectureId: lecture.id,
                  tasks: tasks,
                  jobFailed: jobFailed,
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.starGold,
                onRefresh: () => _handleRefresh(context, ref, lecture: lecture),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 所属コースへのリンク (例: "物理学I ›")。
                      // 「戻る」ではなく「この講義が所属している場所」を示す導線なので、
                      // 左シェブロン(=端末の戻る操作と競合して見える)ではなく末尾の
                      // 右シェブロンにしている。実際の遷移方向はnavigateUpToが
                      // pop/pushを出し分け、アニメーションが自然に表現する。
                      if (course != null || lecture.courseId != null) ...[
                        InkWell(
                          onTap: () => navigateUpTo(
                            context,
                            lecture.courseId != null
                                ? '${AppRoutes.coursesRootPath}/c/${lecture.courseId}'
                                : AppRoutes.coursesRootPath,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chevron_left,
                                  color: themeColor,
                                  size: 22,
                                ),
                                Flexible(
                                  child: Text(
                                    course?.displayTitle ?? l10n.coursePageTitle,
                                    style: TextStyle(
                                      color: themeColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Date (left-aligned) - Moved above collage
                      Text(
                        DateFormat.yMMMd(l10n.localeName).format(
                          lecture.lectureDatetime.toLocal(),
                        ),
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),

                    // Hero Collage View
                    RevealSwitcher(
                      reveal: heroCollageReveal,
                      locked: const ShimmerBox(height: 180, borderRadius: 20),
                      ready: LectureHeroCollage(
                        lectureId: lecture.id,
                        onTap: topics.isNotEmpty
                            ? () => _showTopicsSheet(
                                context,
                                lecture.id,
                                lecture.courseId,
                                topics,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title + Edit Button Row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white70,
                            size: 24,
                          ),
                          onPressed: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) =>
                                  LectureEditSheet(lecture: lecture),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Summary
                    RevealSwitcher(
                      reveal: summaryReveal,
                      locked: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerBox(height: 14, borderRadius: 6),
                          SizedBox(height: 8),
                          ShimmerBox(height: 14, borderRadius: 6),
                          SizedBox(height: 8),
                          ShimmerBox(width: 180, height: 14, borderRadius: 6),
                        ],
                      ),
                      ready: Text(
                        (summary != null && summary.isNotEmpty)
                            ? summary
                            : l10n.lectureViewerSummaryPlaceholder,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Start Review Session Button (horizontal capsule button)
                    // GestureDetector(
                    //   onTap: () {
                    //     ScaffoldMessenger.of(context).showSnackBar(
                    //       const SnackBar(content: Text('Starting Review Session...')),
                    //     );
                    //   },
                    //   child: Container(
                    //     height: 52,
                    //     decoration: BoxDecoration(
                    //       gradient: const LinearGradient(
                    //         colors: [AppColors.starGold, Color(0xFFFFD700)],
                    //       ),
                    //       borderRadius: BorderRadius.circular(26),
                    //       boxShadow: [
                    //         BoxShadow(
                    //           color: AppColors.starGold.withValues(alpha: 0.3),
                    //           blurRadius: 12,
                    //           offset: const Offset(0, 4),
                    //         ),
                    //       ],
                    //     ),
                    //     child: Row(
                    //       mainAxisAlignment: MainAxisAlignment.center,
                    //       children: [
                    //         Icon(Icons.play_circle_fill, color: AppColors.universe.voidBackground, size: 24),
                    //         const SizedBox(width: 8),
                    //         Text(
                    //           'Start Review Session',
                    //           style: TextStyle(
                    //             color: AppColors.universe.voidBackground,
                    //             fontSize: 16,
                    //             fontWeight: FontWeight.bold,
                    //           ),
                    //         ),
                    //       ],
                    //     ),
                    //   ),
                    // ),
                    // const SizedBox(height: 24),

                    // Horizontal Info Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          RevealSwitcher(
                            reveal: announcementsReveal,
                            locked: const ShimmerBox(width: 118, height: 30, borderRadius: 20),
                            ready: _HighlightChip(
                              icon: Icons.campaign_outlined,
                              label: l10n.lectureViewerAnnouncementsChip(
                                announcements.length,
                              ),
                              onTap: announcements.isNotEmpty
                                  ? () => _showAnnouncementsSheet(
                                      context,
                                      lecture.id,
                                      announcements,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RevealSwitcher(
                            reveal: keywordsReveal,
                            locked: const ShimmerBox(width: 96, height: 30, borderRadius: 20),
                            ready: _HighlightChip(
                              icon: Icons.vpn_key_outlined,
                              label: l10n.lectureViewerKeywordsChip(
                                keywords.length,
                              ),
                              onTap: keywords.isNotEmpty
                                  ? () => _showKeywordsSheet(context, keywords, topics)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RevealSwitcher(
                            reveal: topicsReveal,
                            locked: const ShimmerBox(width: 88, height: 30, borderRadius: 20),
                            ready: _HighlightChip(
                              icon: Icons.hub_outlined,
                              label: l10n.lectureViewerTopicsChip(topics.length),
                              onTap: topics.isNotEmpty
                                  ? () => _showTopicsSheet(
                                      context,
                                      lecture.id,
                                      lecture.courseId,
                                      topics,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Two Large Buttons: Review Cards & Deep Notes (横並びでどでかく)
                    Row(
                      children: [
                        Expanded(
                          child: RevealSwitcher(
                            reveal: reviewCardsReveal,
                            locked: const ShimmerBox(height: 96, borderRadius: 18),
                            ready: () {
                              final card = _LargeNavigatorCard(
                                icon: Icons.style_outlined,
                                title: l10n.lectureViewerReviewCardsTitle,
                                onTap: () {
                                  if (isTutorial && !isTutorialCompleted) {
                                    ref.read(userProfileRepositoryProvider).markTutorialCompleted();
                                  }
                                  context.push(
                                    '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/rcv/${lecture.id}?index=0',
                                  );
                                },
                              );
                              if (showReviewCardsTutorialCallout) {
                                return TutorialLectureCallout(
                                  message: l10n.lectureViewerTutorialReviewCardsCallout,
                                  borderRadius: 16,
                                  badgeTop: -14,
                                  badgeRight: 8,
                                  child: card,
                                );
                              }
                              return card;
                            }(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: RevealSwitcher(
                            reveal: deepNotesReveal,
                            locked: const ShimmerBox(height: 96, borderRadius: 18),
                            ready: _LargeNavigatorCard(
                              icon: Icons.description_outlined,
                              title: l10n.lectureViewerDeepNotesTitle,
                              onTap: () => context.push(
                                '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/dnd/${lecture.id}/0',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Fun Fact Section
                    // ★ readyでもfunFacts.isEmptyならSizedBox.shrinkへ収束する
                    // (=タスクは完了したが結果0件、という正常系)。lockedの間は
                    // ヘッダーごとスケルトンにする(readyになった瞬間にヘッダー+
                    // カードがセットで出てくる方が、ヘッダーだけ先に出て中身が
                    // 遅れて来るより落ち着いて見えるため)。
                    RevealSwitcher(
                      reveal: funFactReveal,
                      locked: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.lectureViewerFunFactHeader,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const ShimmerBox(height: 120, borderRadius: 16),
                          const SizedBox(height: 28),
                        ],
                      ),
                      ready: funFacts.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.lectureViewerFunFactHeader,
                                  style: TextStyle(
                                    color: AppColors.universe.textComet,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                KeyedSubtree(
                                  key: funFactKey,
                                  child: _ViewerFunFactCard(fact: funFacts.first),
                                ),
                                const SizedBox(height: 28),
                              ],
                            ),
                    ),

                    RevealSwitcher(
                      reveal: transcriptReveal,
                      locked: const ShimmerBox(height: 52, borderRadius: 12),
                      ready: GestureDetector(
                        onTap: () => context.push(
                          '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/v/${lecture.id}/transcript',
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.universe.glassWhiteLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.universe.glassBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                color: AppColors.starGold,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.lectureViewerTranscriptButtonLabel,
                                style: TextStyle(
                                  color: AppColors.universe.textStarlight,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        l10n.aiDisclaimerText,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
    );

    // ★ ヘッダー(CustomAppBar、プロフィールアイコン/Homeボタン)は常にシャープな
    // まま画面最上部に固定し、ブラー+暗いオーバーレイは進捗バナー〜スクロール
    // 本体(blurredBody)だけにかける。FullScreenRevealBlurは「まだ何一つready
    // なブロックが無い」間だけ有効になり、中央にLectureOverlayCard(NotStarted/
    // Processing/Failedいずれか)を乗せる —— 旧LectureStatusScaffoldが画面ごと
    // 丸ごと切り替えていたのと同じ体験を、要素単位のスケルトンの上に重ねる形で
    // 再現している。
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            themeColor.withValues(alpha: 0.3),
            themeColor.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(showHomeButton: true),
            Expanded(
              child: FullScreenRevealBlur(
                active: !hasAnyReady,
                overlay: LectureOverlayCard(lecture: lecture, uiState: uiState),
                child: blurredBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementsSheet(
    BuildContext context,
    String lectureId,
    List<Announcement> announcements, {
    String? targetAnnouncementId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnnouncementsSheet(
        lectureId: lectureId,
        targetAnnouncementId: targetAnnouncementId,
      ),
    );
  }

  void _showKeywordsSheet(
    BuildContext context,
    List<Keyword> keywords,
    List<LectureTopic> topics,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LectureInfoSheet.keywords(keywords, topics),
    );
  }

  void _showTopicsSheet(
    BuildContext context,
    String lectureId,
    String? courseId,
    List<LectureTopic> topics,
  ) {
    showTopicsSheet(
      context: context,
      lectureId: lectureId,
      courseId: courseId,
      initialTopics: topics,
    );
  }
}

class _LargeNavigatorCard extends StatelessWidget {
  const _LargeNavigatorCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.starGold, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerFunFactCard extends HookConsumerWidget {
  const _ViewerFunFactCard({required this.fact});

  final FunFact fact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hook = fact.hook?.trim();
    final body = fact.body?.trim() ?? '';
    final fullText = (hook != null && hook.isNotEmpty)
        ? '$hook\n\n$body'
        : body;

    final currentReaction = fact.reaction;

    return GlowingRainbowBorder(
      borderRadius: 20.0,
      borderWidth: 1.5,
      glowRadius: 6.0,
      animate: true,
      innerGlow: true,
      glowOpacity: 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fact.title?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 25, 25, 0),
                child: Text(
                  fact.title!.trim(),
                  style: const TextStyle(
                    color: AppColors.starGold,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 12, 25, 16),
              child: Text(
                fullText,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            if (fact.sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 0, 25, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final url in fact.sources) _ViewerFunFactSourceChip(url: url),
                  ],
                ),
              ),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ViewerReactionButton(
                    factId: fact.id,
                    lectureId: fact.lectureId!,
                    reaction: 'like',
                    currentReaction: currentReaction,
                  ),
                  const SizedBox(width: 12),
                  _ViewerReactionButton(
                    factId: fact.id,
                    lectureId: fact.lectureId!,
                    reaction: 'dislike',
                    currentReaction: currentReaction,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerFunFactSourceChip extends StatelessWidget {
  const _ViewerFunFactSourceChip({required this.url});

  final String url;

  String get _label {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    var launched = false;
    if (uri != null) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.lectureViewerFunFactLinkOpenFailedSnackbar)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, color: AppColors.deepGold, size: 12),
            const SizedBox(width: 4),
            Text(
              _label,
              style: const TextStyle(
                color: AppColors.deepGold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerReactionButton extends ConsumerWidget {
  const _ViewerReactionButton({
    required this.factId,
    required this.lectureId,
    required this.reaction,
    required this.currentReaction,
  });

  final String factId;
  final String lectureId;
  final String reaction;
  final String? currentReaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isActive = currentReaction == reaction;

    IconData iconData;
    Color iconColor;
    if (reaction == 'like') {
      iconData = isActive ? Icons.favorite : Icons.favorite_border;
      iconColor = isActive ? Colors.redAccent : Colors.white54;
    } else {
      iconData = isActive ? Icons.thumb_down : Icons.thumb_down_alt_outlined;
      iconColor = isActive ? Colors.blueAccent : Colors.white54;
    }

    return IconButton(
      icon: Icon(iconData, color: iconColor, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () async {
        final newReaction = isActive ? null : reaction;
        try {
          // ローカルDBを即時更新(楽観的UI)。Streamが自動的にUIへ反映するため
          // invalidateは不要。Supabaseへの反映はバックグラウンドのOutbox経由。
          await ref
              .read(funFactRepositoryDriftProvider)
              .updateReaction(id: factId, reaction: newReaction);
          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.lectureViewerReactionUpdateFailedSnackbar(e.toString()),
              ),
            ),
          );
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ヘッダーの「Xお知らせ」「Y Fun Facts」チップ
// ---------------------------------------------------------------------------
class _HighlightChip extends StatelessWidget {
  const _HighlightChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.starGold, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.universe.textComet,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeywordCardTile extends HookConsumerWidget {
  const _KeywordCardTile({
    super.key,
    required this.keyword,
  });

  final Keyword keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isSaved = useState(keyword.isSaved);
    final hasDefinition = keyword.definition?.trim().isNotEmpty == true;

    useEffect(() {
      isSaved.value = keyword.isSaved;
      return null;
    }, [keyword.isSaved]);

    final bg = Colors.white.withValues(alpha: 0.03);
    final border = AppColors.universe.glassBorder;
    final textCl = AppColors.universe.textStarlight;
    final subTextCl = AppColors.universe.textComet;
    final inactIconCl = AppColors.universe.textComet;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () => _showEditKeywordSheet(context, ref, keyword),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      keyword.keyword?.trim().isNotEmpty == true
                          ? keyword.keyword!.trim()
                          : l10n.lectureViewerUntitledTerm,
                      style: TextStyle(
                        color: textCl,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: inactIconCl,
                      size: 18,
                    ),
                    onPressed: () => _showEditKeywordSheet(context, ref, keyword),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      isSaved.value ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: isSaved.value ? AppColors.growthGreen : inactIconCl,
                      size: 20,
                    ),
                    onPressed: () async {
                      final newSavedState = !isSaved.value;
                      isSaved.value = newSavedState;

                      final uid = supabase.auth.currentUser?.id;
                      if (uid == null) return;

                      await ref.read(keywordRepositoryDriftProvider).toggleSaveKeyword(
                            keywordId: keyword.id,
                            userId: uid,
                            isSaved: newSavedState,
                            existingMetadataJson: keyword.metadataJson,
                          );
                      ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                    },
                  ),
                ],
              ),
              if (hasDefinition) ...[
                const SizedBox(height: 6),
                Text(
                  keyword.definition!.trim(),
                  style: TextStyle(
                    color: subTextCl,
                    fontSize: 14,
                    height: 1.4,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _showEditKeywordSheet(
  BuildContext context,
  WidgetRef ref,
  Keyword keyword,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EditKeywordSheet(keyword: keyword),
  );
}

class _EditKeywordSheet extends HookConsumerWidget {
  const _EditKeywordSheet({required this.keyword});

  final Keyword keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final termController = useTextEditingController(text: keyword.keyword ?? '');
    final defController = useTextEditingController(text: keyword.definition ?? '');
    final isSaving = useState(false);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppColors.universe.glassBorder),
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.editKeywordDialogTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: AppColors.universe.textComet),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.editKeywordTermLabel,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: termController,
              style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
              decoration: InputDecoration(
                hintText: l10n.editKeywordTermHint,
                hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.universe.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.universe.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.starGold),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.editKeywordDefinitionLabel,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: defController,
              maxLines: 4,
              minLines: 2,
              style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
              decoration: InputDecoration(
                hintText: l10n.editKeywordDefinitionHint,
                hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.universe.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.universe.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.starGold),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isSaving.value ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.editKeywordCancelButton,
                    style: TextStyle(color: AppColors.universe.textComet),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: isSaving.value
                      ? null
                      : () async {
                          final newTerm = termController.text.trim();
                          final newDef = defController.text.trim();
                          if (newTerm.isEmpty) return;

                          final uid = supabase.auth.currentUser?.id;
                          if (uid == null) return;

                          isSaving.value = true;
                          try {
                            await ref.read(keywordRepositoryDriftProvider).updateKeyword(
                                  keywordId: keyword.id,
                                  userId: uid,
                                  keyword: newTerm,
                                  definition: newDef.isEmpty ? null : newDef,
                                );
                            ref.read(lectureControllerProvider.notifier).pushOutboxNow();

                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } finally {
                            isSaving.value = false;
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSaving.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(l10n.editKeywordSaveButton, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 「Xお知らせ」「Y Fun Facts」チップをタップした時に開くボトムシート
// ---------------------------------------------------------------------------
enum _LectureInfoSheetKind { announcements, keywords }

class _LectureInfoSheet extends ConsumerWidget {
  const _LectureInfoSheet._({
    required this.kind,
    required this.itemsBuilder,
  });



  factory _LectureInfoSheet.keywords(
    List<Keyword> keywords,
    List<LectureTopic> topics,
  ) {
    return _LectureInfoSheet._(
      kind: _LectureInfoSheetKind.keywords,
      itemsBuilder: (context, ref) {
        final topicMap = <int, LectureTopic>{
          for (final t in topics) t.index: t,
        };

        final groupedKeywords = <int, List<Keyword>>{};
        for (final k in keywords) {
          groupedKeywords.putIfAbsent(k.topicNumber, () => []).add(k);
        }

        final widgets = <Widget>[];
        final sortedTopicNumbers = <int>{
          ...topics.map((t) => t.index),
          ...groupedKeywords.keys,
        }.toList()..sort();

        for (final topicNum in sortedTopicNumbers) {
          final kwList = groupedKeywords[topicNum];
          if (kwList == null || kwList.isEmpty) continue;

          final topic = topicMap[topicNum];
          final topicTitle = topic?.displayTitle ?? 'Topic $topicNum';

          widgets.add(_TopicSectionHeader(
            topicNumber: topicNum,
            title: topicTitle,
            isFirst: widgets.isEmpty,
          ));

          for (final k in kwList) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _KeywordCardTile(
                  key: ValueKey(k.id),
                  keyword: k,
                ),
              ),
            );
          }
        }

        return widgets;
      },
    );
  }

  final _LectureInfoSheetKind kind;
  final List<Widget> Function(BuildContext context, WidgetRef ref) itemsBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = switch (kind) {
      _LectureInfoSheetKind.announcements => l10n.lectureViewerAnnouncementsSheetTitle,
      _LectureInfoSheetKind.keywords => l10n.lectureViewerKeywordsSheetTitle,
    };
    final items = itemsBuilder(context, ref);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: AppColors.universe.glassBorder),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.lectureViewerInfoSheetEmptyState,
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: items.length,
                        itemBuilder: (context, index) => items[index],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopicSectionHeader extends StatelessWidget {
  const _TopicSectionHeader({
    required this.topicNumber,
    required this.title,
    this.isFirst = false,
  });

  final int topicNumber;
  final String title;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    String cleanTitle = title;
    final prefix = 'Topic $topicNumber';
    if (cleanTitle.startsWith(prefix)) {
      cleanTitle = cleanTitle.substring(prefix.length).trim();
      cleanTitle = cleanTitle.replaceAll(RegExp(r'^[:：\s]+'), '');
    }

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4.0 : 16.0, bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isFirst) ...[
            Divider(
              color: AppColors.universe.glassBorder.withValues(alpha: 0.5),
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.starGold.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Topic $topicNumber',
                  style: const TextStyle(
                    color: AppColors.starGold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (cleanTitle.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cleanTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _handleRefresh(
  BuildContext context,
  WidgetRef ref, {
  required Lecture lecture,
}) async {
  if (!await isDeviceOnline()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).coursePageOfflineSnackbar,
          ),
        ),
      );
    }
    return;
  }

  // 1. 最新の講義・ジョブ状態を同期
  await ref.read(lectureControllerProvider.notifier).bootstrapLectures(
        reason: 'lecture_viewer_pull_to_refresh',
      );

  // 2. 講義配下の各コンテンツを最新化
  final db = ref.read(appDatabaseProvider);
  try {
    await Future.wait([
      LectureTopicSyncService(db).pullForLecture(lecture.id),
      ReviewCardSyncService(db).pullForLecture(lecture.id),
      DeepNoteSyncService(db).pullForLecture(lecture.id),
      FunFactSyncService(db).pullForLecture(lecture.id),
      KeywordSyncService(db).pullForLecture(lecture.id),
      AnnouncementSyncService(db).pull(forceFullPull: true),
    ]);
  } catch (e, st) {
    DevLog.add('⚠️ [LectureViewerPage] Pull-to-refresh content sync error: $e\n$st');
  }

  // 3. 各種Stream/Providerを再読込
  ref.invalidate(lectureTopicsProvider(lecture.id));
  ref.invalidate(lectureKeywordsProvider(lecture.id));
  ref.invalidate(funFactsForLectureProvider(lecture.id));
  ref.invalidate(announcementsForLectureProvider(lecture.id));
  ref.invalidate(reviewCardsProvider(lecture.id));
  ref.invalidate(deepNotesProvider(lecture.id));
  ref.invalidate(jobStreamProvider(lecture.id));
  ref.invalidate(allLecturesStreamProvider);
  if (lecture.courseId != null) {
    ref.invalidate(courseListProvider);
  }
}

