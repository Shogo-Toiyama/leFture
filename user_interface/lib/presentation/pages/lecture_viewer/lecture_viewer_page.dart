import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_content_recovery.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/domain/entities/keyword.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/lecture_artifact_repository.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_tile.dart';
import 'package:lecture_companion_ui/presentation/widgets/glowing_rainbow_border.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/keyword_repository_drift.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_state_providers.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/announcement_edit_sheet.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/lecture_status_scaffold.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/widgets/lecture_hero_collage.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

class LectureViewerPage extends HookConsumerWidget {
  const LectureViewerPage({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        body: _LectureViewerBody(lecture: dummyLecture),
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
            'Error: $err',
            style: const TextStyle(color: AppColors.correctionRed),
          ),
        ),
      ),
      data: (lecture) {
        if (lecture == null) {
          return Scaffold(
            backgroundColor: AppColors.universe.voidBackground,
            body: const Center(
              child: Text(
                'Lecture not found',
                style: TextStyle(color: Colors.white),
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
                'Error: $err',
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
                body: _LectureViewerBody(lecture: lecture),
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
                    return _LecturePageContent(lecture: lectureItem);
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
  const _LecturePageContent({required this.lecture});

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStateAsync = ref.watch(lectureStateProvider(lecture.id));

    ref.listen<AsyncValue<LectureUIState>>(lectureStateProvider(lecture.id), (
      previous,
      next,
    ) {
      next.whenData((state) {
        if (state == LectureUIState.complete) {
          final uid = supabase.auth.currentUser?.id;
          if (uid != null) {
            ref.invalidate(transcriptProvider(uid: uid, lectureId: lecture.id));
          }
          ref.read(lectureControllerProvider.notifier).bootstrapLectures();
        }
      });
    });

    return uiStateAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.starGold),
      ),
      error: (err, stack) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.correctionRed),
        ),
      ),
      data: (uiState) {
        if (uiState == LectureUIState.complete) {
          return _LectureViewerBody(lecture: lecture);
        }

        return LectureStatusScaffold(lecture: lecture);
      },
    );
  }
}

class _LectureViewerBody extends HookConsumerWidget {
  const _LectureViewerBody({required this.lecture});

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final courseCode = course?.courseCode ?? 'N/A';

    final displayTitle = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true
              ? lecture.titleGenerated!
              : 'Untitled Lecture');
    final summary = lecture.summary == null
        ? null
        : stripSidCitations(lecture.summary!).trim();
    final themeColor = CourseStyleHelper.hexToColor(
      course?.color,
      fallback: AppColors.starGold,
    );

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Date & Course Code (left-aligned) - Moved above collage
                    Row(
                      children: [
                        Text(
                          DateFormat.yMMMd().format(
                            lecture.lectureDatetime.toLocal(),
                          ),
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: AppColors.universe.textComet.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          courseCode,
                          style: const TextStyle(
                            color: AppColors.starGold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Hero Collage View
                    LectureHeroCollage(lectureId: lecture.id),
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
                    Text(
                      (summary != null && summary.isNotEmpty)
                          ? summary
                          : 'This lecture is still being analyzed. The summary will appear here once it\'s ready.',
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 14,
                        height: 1.5,
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
                          _HighlightChip(
                            icon: Icons.campaign_outlined,
                            label:
                                '${announcements.length} announcement${announcements.length == 1 ? '' : 's'}',
                            onTap: announcements.isNotEmpty
                                ? () => _showAnnouncementsSheet(
                                    context,
                                    lecture.id,
                                    announcements,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _HighlightChip(
                            icon: Icons.vpn_key_outlined,
                            label:
                                '${keywords.length} keyword${keywords.length == 1 ? '' : 's'}',
                            onTap: keywords.isNotEmpty
                                ? () => _showKeywordsSheet(context, keywords)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _HighlightChip(
                            icon: Icons.hub_outlined,
                            label:
                                '${topics.length} topic${topics.length == 1 ? '' : 's'}',
                            onTap: null, // Dummy/no-op
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Two Large Buttons: Review Cards & Deep Notes (横並びでどでかく)
                    Row(
                      children: [
                        Expanded(
                          child: _LargeNavigatorCard(
                            icon: Icons.style_outlined,
                            title: 'Review Cards',
                            onTap: () => context.push(
                              '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/rcv/${lecture.id}?index=0',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _LargeNavigatorCard(
                            icon: Icons.description_outlined,
                            title: 'Deep Notes',
                            onTap: () => context.push(
                              '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/dnd/${lecture.id}/0',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Fun Fact Section
                    if (funFacts.isNotEmpty) ...[
                      Text(
                        'FUN FACT',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ViewerFunFactCard(fact: funFacts.first),
                      const SizedBox(height: 28),
                    ],

                    GestureDetector(
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
                              'Transcript',
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
                  ],
                ),
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
    List<Announcement> announcements,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LectureInfoSheet.announcements(
        lectureId: lectureId,
        announcements: announcements,
      ),
    );
  }

  void _showKeywordsSheet(BuildContext context, List<Keyword> keywords) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LectureInfoSheet.keywords(keywords),
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
            SnackBar(content: Text('Failed to update reaction: $e')),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.subtitleColor,
    this.inactiveIconColor,
  });

  final Keyword keyword;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final Color? subtitleColor;
  final Color? inactiveIconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = useState(keyword.isSaved);
    final hasDefinition = keyword.definition?.trim().isNotEmpty == true;

    useEffect(() {
      isSaved.value = keyword.isSaved;
      return null;
    }, [keyword.isSaved]);

    final bg = backgroundColor ?? Colors.white.withValues(alpha: 0.03);
    final border = borderColor ?? AppColors.universe.glassBorder;
    final textCl = textColor ?? AppColors.universe.textStarlight;
    final subTextCl = subtitleColor ?? AppColors.universe.textComet;
    final inactIconCl = inactiveIconColor ?? AppColors.universe.textComet;

    return Container(
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
                      : 'Untitled term',
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
    );
  }
}

// ---------------------------------------------------------------------------
// 「Xお知らせ」「Y Fun Facts」チップをタップした時に開くボトムシート
// ---------------------------------------------------------------------------
class _LectureInfoSheet extends ConsumerWidget {
  const _LectureInfoSheet._({
    required this.title,
    required this.itemsBuilder,
    this.lectureId,
  });

  factory _LectureInfoSheet.announcements({
    required String lectureId,
    required List<Announcement> announcements,
  }) {
    return _LectureInfoSheet._(
      title: 'Announcements',
      lectureId: lectureId,
      itemsBuilder: (context, ref) {
        // 最新の状態を NotifierProvider から直接取得（スワイプ後の状態変化を反映）
        final currentAnnouncements =
            ref
                .watch(announcementsForLectureProvider(lectureId))
                .asData
                ?.value ??
            announcements;
        return currentAnnouncements
            .map(
              (a) => AnnouncementTile(
                key: ValueKey(a.id),
                announcement: a,
                showTimestamp: false,
                onToggleComplete: (ann) async {
                  await ref
                      .read(announcementRepositoryDriftProvider)
                      .toggleComplete(id: ann.id, completed: !ann.isCompleted);
                  ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                },
                onEdit: () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AnnouncementEditSheet(announcement: a),
                  );
                },
                onDelete: (Announcement ann) async {
                  await ref
                      .read(announcementRepositoryDriftProvider)
                      .softDeleteAnnouncement(id: ann.id);
                  ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                },
              ),
            )
            .toList();
      },
    );
  }

  factory _LectureInfoSheet.keywords(List<Keyword> keywords) {
    return _LectureInfoSheet._(
      title: 'Keywords',
      itemsBuilder: (context, ref) => keywords.map((k) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _KeywordCardTile(
            key: ValueKey(k.id),
            keyword: k,
          ),
        );
      }).toList(),
    );
  }

  final String title;
  final String? lectureId;
  final List<Widget> Function(BuildContext context, WidgetRef ref) itemsBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                          'Nothing here yet',
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: items.length,
                        separatorBuilder: (context, _) =>
                            const SizedBox(height: 10),
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

/*
class _FunFactRow extends StatelessWidget {
  const _FunFactRow({required this.funFact});

  final FunFact funFact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            funFact.title?.trim().isNotEmpty == true ? funFact.title!.trim() : 'Fun Fact',
            style: const TextStyle(
              color: AppColors.starGold,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          if (funFact.hook?.trim().isNotEmpty == true) ...[
            MarkdownBody(
              data: stripSidCitations(funFact.hook!.trim()),
              styleSheet: _funFactStyle(
                TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                context,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (funFact.body?.trim().isNotEmpty == true)
            MarkdownBody(
              data: stripSidCitations(funFact.body!.trim()),
              styleSheet: _funFactStyle(
                TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4),
                context,
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _funFactStyle(TextStyle base, BuildContext context) {
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.bold, color: AppColors.universe.textStarlight),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: AppColors.starGold),
    );
  }
}

// ---------------------------------------------------------------------------
// Keywords View
// ---------------------------------------------------------------------------
class _KeywordsView extends HookConsumerWidget {
  const _KeywordsView({super.key, required this.keywords});

  final List<Keyword> keywords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (keywords.isEmpty) {
      return Center(
        child: Text(
          'No keywords yet',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keywords.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final k = keywords[index];
        return _KeywordCardTile(
          key: ValueKey(k.id),
          keyword: k,
          backgroundColor: AppColors.paper.surface,
          borderColor: Colors.black.withValues(alpha: 0.06),
          textColor: Theme.of(context).colorScheme.onSurface,
          subtitleColor: Theme.of(context).colorScheme.onSurfaceVariant,
          inactiveIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// 1. Review Cards View
// ---------------------------------------------------------------------------
/// Review Cardsタブのフラットなカード1枚分。[card]がnullなら表紙(トピック画像+タイトル)。
class _ReviewCardItem {
  const _ReviewCardItem({required this.groupIndex, this.card});

  final int groupIndex;
  final ReviewCard? card;

  bool get isCover => card == null;
}

class _ReviewCardsView extends HookConsumerWidget {
  const _ReviewCardsView({
    super.key,
    required this.isExpanded,
    required this.currentCardIndex,
    required this.onExpand,
    required this.groups,
  });

  final bool isExpanded;
  final ValueNotifier<int> currentCardIndex;
  final VoidCallback onExpand;
  final List<_ReviewTopicGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );
    useAnimation(animationController);

    final previousCardIndex = useState<int>(currentCardIndex.value);
    final isAnimating = useState<bool>(false);
    final isGoingForward = useState<bool>(true);

    final screenWidth = MediaQuery.of(context).size.width;

    // groupsを「表紙 + コンテンツカード」のフラットな1本のリストに展開する。
    // 「フラットindex -> どのgroupか」「groupごとの開始index」も併せて作っておく。
    final flatItems = useMemoized(() {
      final list = <_ReviewCardItem>[];
      for (var gi = 0; gi < groups.length; gi++) {
        list.add(_ReviewCardItem(groupIndex: gi)); // 表紙
        for (final card in groups[gi].cards) {
          list.add(_ReviewCardItem(groupIndex: gi, card: card));
        }
      }
      return list;
    }, [groups]);

    final groupStartIndex = useMemoized(() {
      final starts = <int>[];
      var idx = 0;
      for (final g in groups) {
        starts.add(idx);
        idx += g.cards.length + 1; // +1は表紙
      }
      return starts;
    }, [groups]);

    final totalCards = flatItems.length;

    // トピック画像 (R2からローカルキャッシュ経由で取得)。groupIndex -> File?
    final imageFiles = <int, File?>{};
    for (var gi = 0; gi < groups.length; gi++) {
      final path = groups[gi].imagePath;
      imageFiles[gi] =
          path == null ? null : ref.watch(artifactFileProvider(path)).asData?.value;
    }

    final navigateTo = useCallback((int newIndex, {bool immediate = false}) {
      if (isAnimating.value || newIndex == currentCardIndex.value) return;
      if (immediate) {
        currentCardIndex.value = newIndex;
        previousCardIndex.value = newIndex;
        return;
      }
      previousCardIndex.value = currentCardIndex.value;
      isGoingForward.value = newIndex > currentCardIndex.value;
      currentCardIndex.value = newIndex;
      isAnimating.value = true;
      animationController.forward(from: 0.0).then((_) {
        isAnimating.value = false;
        previousCardIndex.value = newIndex;
      });
    }, [currentCardIndex.value, isAnimating.value]);

    Widget buildCard(int cardIdx) {
      final item = flatItems[cardIdx.clamp(0, totalCards - 1)];
      final imageFile = imageFiles[item.groupIndex];

      if (item.isCover) {
        return _CoverCard(
          title: groups[item.groupIndex].title,
          imageFile: imageFile,
          borderRadius: 24,
        );
      }
      return _ContentCard(card: item.card!, imageFile: imageFile);
    }

    if (totalCards == 0) {
      return Center(
        child: Text(
          'No review cards yet',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (!isExpanded) {
      // Collapsed State: Card Dashboard (Start button + Horizontal Scroll Rows)
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length + 1,
        separatorBuilder: (context, _) => const SizedBox(height: 24),
        itemBuilder: (context, topicIdx) {
          if (topicIdx == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: GestureDetector(
                onTap: () {
                  navigateTo(0, immediate: true);
                  onExpand();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.starGold, Color(0xFFFFD700)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_fill, color: AppColors.universe.voidBackground, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Start Review Session!',
                        style: TextStyle(
                          color: AppColors.universe.voidBackground,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final group = groups[topicIdx - 1];
          final groupStart = groupStartIndex[topicIdx - 1];
          final imageFile = imageFiles[topicIdx - 1];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic Header
              Text(
                group.title,
                style: TextStyle(
                  color: AppColors.paper.textInk,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),

              // 横スクロールのカード列: 先頭は表紙(画像入り)、続けてコンテンツカード
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: group.cards.length + 1,
                  separatorBuilder: (context, _) => const SizedBox(width: 12),
                  itemBuilder: (context, tileIdx) {
                    if (tileIdx == 0) {
                      // 表紙タイル
                      return GestureDetector(
                        onTap: () {
                          navigateTo(groupStart, immediate: true);
                          onExpand();
                        },
                        child: SizedBox(
                          width: 110,
                          child: _CoverCard(
                            title: group.title,
                            imageFile: imageFile,
                            borderRadius: 16,
                            compact: true,
                          ),
                        ),
                      );
                    }

                    final card = group.cards[tileIdx - 1];
                    final preview = card.title?.trim().isNotEmpty == true
                        ? card.title!.trim()
                        : plainTextPreview(
                            card.cardContent.isNotEmpty ? (card.cardContent.first.text ?? '') : '');
                    return GestureDetector(
                      onTap: () {
                        navigateTo(groupStart + tileIdx, immediate: true);
                        onExpand();
                      },
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.paper.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (card.heroEmoji?.trim().isNotEmpty == true) ...[
                              Text(card.heroEmoji!.trim(), style: const TextStyle(fontSize: 24)),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              preview,
                              style: TextStyle(
                                color: AppColors.paper.textInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    }

    // Expanded State: Immersive Instagram Stories-style Card Viewer
    final index = currentCardIndex.value.clamp(0, totalCards - 1);
    final currentGroupIndex = flatItems[index].groupIndex;
    final topic = groups[currentGroupIndex];

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Topic Title above the card
          Text(
            topic.title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 2. Stories Progress Indicators (Grouped by Topic, 表紙も1本として数える)
          Row(
            children: List.generate(groups.length, (topicIdx) {
              final group = groups[topicIdx];
              final groupStart = groupStartIndex[topicIdx];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: List.generate(group.cards.length + 1, (cardIdx) {
                      final absIdx = groupStart + cardIdx;
                      final isFilled = absIdx <= currentCardIndex.value;
                      final isActive = absIdx == currentCardIndex.value;

                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final activeColor = Theme.of(context).colorScheme.primary;
                      final filledColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
                      final unfilledColor = isDark ? Colors.white12 : Colors.black12;

                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isActive
                                ? activeColor
                                : isFilled
                                    ? filledColor
                                    : unfilledColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 3. Card Area
          // タップ判定はカードを覆うオーバーレイではなく、この親GestureDetectorのonTapUpで行う。
          // (オーバーレイ方式だとカード内のスクロールジェスチャーを奪ってしまうため。
          //  Scrollableは縦ドラッグのみを主張するので、タップは親に届き、縦スクロールは
          //  カード内のSingleChildScrollViewが処理する。)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final cardWidth = screenWidth - 32;
                if (details.localPosition.dx < cardWidth * 0.3) {
                  // 左30%タップ → 前のカード
                  if (currentCardIndex.value > 0) {
                    navigateTo(currentCardIndex.value - 1);
                  }
                } else {
                  // 右70%タップ → 次のカード
                  if (currentCardIndex.value < totalCards - 1) {
                    navigateTo(currentCardIndex.value + 1);
                  }
                }
              },
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                // Swipe Left (velocity < -300) -> Next Topic
                if (details.primaryVelocity! < -300) {
                  if (currentGroupIndex < groups.length - 1) {
                    navigateTo(groupStartIndex[currentGroupIndex + 1]);
                  }
                }
                // Swipe Right (velocity > 300) -> Previous Topic
                else if (details.primaryVelocity! > 300) {
                  if (currentGroupIndex > 0) {
                    navigateTo(groupStartIndex[currentGroupIndex - 1]);
                  }
                }
              },
              child: Builder(
                builder: (context) {
                  if (isAnimating.value) {
                    final progress = animationController.value;
                    if (isGoingForward.value) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: 0.92 + (0.08 * progress),
                              child: Opacity(
                                opacity: 0.5 + (0.5 * progress),
                                child: buildCard(currentCardIndex.value),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(-progress * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -progress * 0.2,
                                alignment: Alignment.bottomCenter,
                                child: buildCard(previousCardIndex.value),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: 1.0 - (0.08 * progress),
                              child: Opacity(
                                opacity: 1.0 - (0.5 * progress),
                                child: buildCard(previousCardIndex.value),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(-(1.0 - progress) * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -(1.0 - progress) * 0.2,
                                alignment: Alignment.bottomCenter,
                                child: buildCard(currentCardIndex.value),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  } else {
                    return buildCard(currentCardIndex.value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// トピックの表紙カード。画像を全面に敷き、その上にタイトルを重ねる。
/// 画像の色味が読めないため、タイトルは半透明の白帯 + 白縁取りの黒文字で保護する。
class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.title,
    required this.imageFile,
    required this.borderRadius,
    this.compact = false,
  });

  final String title;
  final File? imageFile;
  final double borderRadius;

  /// ダッシュボードの小さいタイル用 (フォント等を縮小)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: Colors.black,
      fontSize: compact ? 12 : 22,
      fontWeight: FontWeight.bold,
      height: 1.3,
      // 白縁取り (ハロー) で画像の色に負けないようにする
      shadows: const [
        Shadow(color: Colors.white, blurRadius: 2),
        Shadow(color: Colors.white, blurRadius: 4),
        Shadow(color: Colors.white, blurRadius: 8),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageFile != null)
            Image.file(imageFile!, fit: BoxFit.cover)
          else
            // 画像がまだ無い場合のフォールバック背景
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                ),
              ),
            ),
          // タイトル帯 (半透明の白)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 20,
                vertical: compact ? 8 : 16,
              ),
              color: Colors.white.withValues(alpha: 0.72),
              child: Text(
                title,
                style: titleStyle,
                textAlign: TextAlign.center,
                maxLines: compact ? 3 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// コンテンツカード。トピック画像がある場合はカードの縁に画像が覗くよう、
/// 画像を背景全面に敷いた上で、少し内側に本文パネルを重ねる。
class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.card, required this.imageFile});

  final ReviewCard card;
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageFile != null;

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(hasImage ? 20 : 28),
      child: Column(
        children: [
          Text(
            card.heroEmoji?.trim().isNotEmpty == true ? card.heroEmoji!.trim() : '💡',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 24),
          if (card.title?.trim().isNotEmpty == true) ...[
            Text(
              card.title!.trim(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          ...card.cardContent.map((block) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReviewCardBlockView(block: block),
              )),
        ],
      ),
    );

    if (!hasImage) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.universe.glassWhiteLow : AppColors.paper.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.universe.glassBorder : Colors.black.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // 縁として画像を見せるための余白
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: (isDark ? AppColors.universe.voidBackground : AppColors.paper.surface)
              .withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}

/// review_cards.card_content の1ブロック（paragraph / quote / list）を描画する。
/// テキストはMarkdown(太字など)を含むためMarkdownBodyで描画し、SID引用は除去する。
class _ReviewCardBlockView extends StatelessWidget {
  const _ReviewCardBlockView({required this.block});

  final ReviewCardBlock block;

  MarkdownStyleSheet _styleSheet(BuildContext context, {bool italic = false}) {
    final baseColor = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9);
    final style = TextStyle(
      color: baseColor,
      fontSize: 15,
      height: 1.4,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: style,
      strong: style.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      em: style.copyWith(fontStyle: FontStyle.italic),
      code: style.copyWith(fontFamily: 'monospace', backgroundColor: Colors.transparent),
      listBullet: style.copyWith(color: AppColors.starGold),
      textAlign: WrapAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'quote':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.starGold, width: 3)),
          ),
          child: MarkdownBody(
            data: stripSidCitations(block.text ?? ''),
            styleSheet: _styleSheet(context, italic: true).copyWith(textAlign: WrapAlignment.start),
          ),
        );
      case 'list':
        final items = block.items ?? const <String>[];
        // 各itemをMarkdownの箇条書きにまとめて1つのMarkdownBodyで描画する
        final markdown = items.map((item) => '- ${stripSidCitations(item)}').join('\n');
        return MarkdownBody(
          data: markdown,
          styleSheet: _styleSheet(context).copyWith(textAlign: WrapAlignment.start),
        );
      case 'paragraph':
      default:
        return MarkdownBody(
          data: stripSidCitations(block.text ?? ''),
          styleSheet: _styleSheet(context),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// 2. Deep Notes View
// ---------------------------------------------------------------------------
class _DeepNotesView extends HookWidget {
  const _DeepNotesView({
    super.key,
    required this.isExpanded,
    required this.selectedNoteIndex,
    required this.onExpand,
    required this.selectedText,
    required this.topics,
  });

  final bool isExpanded;
  final ValueNotifier<int?> selectedNoteIndex;
  final VoidCallback onExpand;
  final ValueNotifier<String?> selectedText;
  final List<_NoteTopic> topics;

  @override
  Widget build(BuildContext context) {
    final shouldStartAtBottom = useState(false);
    final noteIndex = selectedNoteIndex.value;

    if (topics.isEmpty) {
      return Center(
        child: Text(
          'Deep notes are being generated…',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: noteIndex == null
          ? _buildNoteList(context)
          : _NoteDetailView(
              key: ValueKey('note_detail_$noteIndex'),
              noteIndex: noteIndex,
              topic: topics[noteIndex],
              totalTopics: topics.length,
              startAtBottom: shouldStartAtBottom.value,
              selectedText: selectedText,
              onNext: () {
                if (noteIndex < topics.length - 1) {
                  shouldStartAtBottom.value = false;
                  selectedNoteIndex.value = noteIndex + 1;
                }
              },
              onPrev: () {
                if (noteIndex > 0) {
                  shouldStartAtBottom.value = true;
                  selectedNoteIndex.value = noteIndex - 1;
                }
              },
            ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('note_list'),
      padding: const EdgeInsets.all(16),
      itemCount: topics.length,
      separatorBuilder: (context, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return GestureDetector(
          onTap: () {
            selectedNoteIndex.value = index;
            onExpand();
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.paper.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (topic.summary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          topic.summary,
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary, size: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDetailView extends HookWidget {
  const _NoteDetailView({
    super.key,
    required this.noteIndex,
    required this.topic,
    required this.totalTopics,
    required this.startAtBottom,
    required this.onNext,
    required this.onPrev,
    required this.selectedText,
  });

  final int noteIndex;
  final _NoteTopic topic;
  final int totalTopics;
  final bool startAtBottom;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final ValueNotifier<String?> selectedText;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final isTransitioning = useState(false);
    
    // Markers to track where scroll gestures start
    final startedAtTop = useState(false);
    final startedAtBottom = useState(false);
    final shouldGoToNext = useState(false);
    final shouldGoToPrev = useState(false);

    // Jump to bottom if startAtBottom is true
    useEffect(() {
      if (startAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
      return null;
    }, [noteIndex]);

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (isTransitioning.value) return false;
                
                // Track where scroll starts
                if (notification is ScrollStartNotification) {
                  final metrics = notification.metrics;
                  startedAtTop.value = metrics.pixels <= 0.0;
                  startedAtBottom.value = metrics.pixels >= metrics.maxScrollExtent;
                  shouldGoToNext.value = false;
                  shouldGoToPrev.value = false;
                }
                
                // Trigger transitions ONLY when the user releases their finger (dragDetails becomes null)
                if (notification is ScrollEndNotification || 
                    (notification is ScrollUpdateNotification && notification.dragDetails == null)) {
                  if (shouldGoToNext.value) {
                    shouldGoToNext.value = false;
                    shouldGoToPrev.value = false;
                    isTransitioning.value = true;
                    onNext();
                  } else if (shouldGoToPrev.value) {
                    shouldGoToNext.value = false;
                    shouldGoToPrev.value = false;
                    isTransitioning.value = true;
                    onPrev();
                  }
                }
                
                // Detect overscroll boundaries
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  final isDragging = notification.dragDetails != null;
                  
                  if (isDragging) {
                    if (startedAtBottom.value && metrics.pixels >= metrics.maxScrollExtent + 50 && noteIndex < totalTopics - 1) {
                      shouldGoToNext.value = true;
                    }
                    if (startedAtTop.value && metrics.pixels <= metrics.minScrollExtent - 50 && noteIndex > 0) {
                      shouldGoToPrev.value = true;
                    }

                    // Reset page turn intent if user scrolls back before releasing
                    if (shouldGoToNext.value && metrics.pixels < metrics.maxScrollExtent + 10) {
                      shouldGoToNext.value = false;
                    }
                    if (shouldGoToPrev.value && metrics.pixels > metrics.minScrollExtent - 10) {
                      shouldGoToPrev.value = false;
                    }
                  }
                }
                
                if (notification is ScrollEndNotification) {
                  startedAtTop.value = false;
                  startedAtBottom.value = false;
                }
                return false;
              },
              child: SelectionArea(
                onSelectionChanged: (content) {
                  selectedText.value = content?.plainText;
                },
                contextMenuBuilder: (context, selectableRegionState) {
                  return const SizedBox.shrink(); // Suppress standard OS selection menu
                },
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  children: [
                    // Upper Arrow indicator (if previous note exists)
                    if (noteIndex > 0)
                      Center(
                        child: Column(
                          children: [
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_up, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onPrev,
                            ),
                            const Text(
                              'Pull or tap to previous note',
                              style: TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),

                    Text(
                      topic.title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (topic.summary.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        topic.summary,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    MarkdownBody(
                      data: topic.content.isNotEmpty
                          ? topic.content
                          : 'Deep notes for this topic are still being generated…',
                      selectable: false,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        h1: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        listBullet: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.starGold
                              : AppColors.deepGold,
                          fontSize: 16,
                        ),
                        code: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.greenAccent
                              : const Color(0xFF0F766E),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          backgroundColor: Colors.transparent,
                        ),
                        codeblockPadding: const EdgeInsets.all(16),
                        codeblockDecoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black45
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.universe.glassBorder
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Lower Arrow indicator (if next note exists)
                    if (noteIndex < totalTopics - 1)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onNext,
                            ),
                            const Text(
                              'Pull or tap to next note',
                              style: TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Transcript View
// ---------------------------------------------------------------------------
class _TranscriptView extends StatelessWidget {
  const _TranscriptView({super.key, required this.transcriptAsync});

  final AsyncValue<List<TranscriptSentence>?> transcriptAsync;

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return transcriptAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
      error: (err, _) => Center(
        child: Text(
          err is ArtifactOfflineException
              ? "You're offline. Transcript will load once you're back online."
              : 'Transcript unavailable',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      data: (sentences) {
        if (sentences == null || sentences.isEmpty) {
          return Center(
            child: Text(
              'Transcript is being generated…',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }
        return Container(
          color: Colors.transparent,
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: sentences.length,
            separatorBuilder: (context, _) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final sentence = sentences[index];
              final isSideChatter = sentence.role != 'lecture';
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatMs(sentence.start),
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      sentence.text,
                      style: TextStyle(
                        color: isSideChatter
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        height: 1.5,
                        fontStyle: isSideChatter ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
*/

/*
class _MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;

  const _MeasureSize({
    required this.onChange,
    required this.child,
  });

  @override
  _MeasureSizeState createState() => _MeasureSizeState();
}

typedef OnWidgetSizeChange = void Function(Size size);

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          widget.onChange(box.size);
        }
      }
    });
    return widget.child;
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
*/
