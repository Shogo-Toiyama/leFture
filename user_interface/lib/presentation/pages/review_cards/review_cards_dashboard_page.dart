// lib/presentation/pages/review_cards/review_cards_dashboard_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/core/utils/text_preview.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';


// ---------------------------------------------------------------------------
// Private data class
// ---------------------------------------------------------------------------
class _ReviewTopicGroup {
  _ReviewTopicGroup({
    required this.topicNumber,
    required this.title,
    required this.cards,
    this.imagePath,
  });

  final int topicNumber;
  final String title;
  final List<ReviewCard> cards;
  final String? imagePath;
}

// ---------------------------------------------------------------------------
// Dashboard Page
// ---------------------------------------------------------------------------
class ReviewCardsDashboardPage extends HookConsumerWidget {
  const ReviewCardsDashboardPage({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final lecture = lectureAsync.asData?.value;
    final courseId = lecture?.courseId ?? 'N/A';

    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final cardsAsync  = ref.watch(reviewCardsProvider(lectureId));

    final groups = useMemoized(() {
      final topics = topicsAsync.asData?.value ?? <LectureTopic>[];
      final cards  = cardsAsync.asData?.value  ?? <ReviewCard>[];
      final map = <int, List<ReviewCard>>{};
      for (final c in cards) {
        map.putIfAbsent(c.topicNumber, () => []).add(c);
      }
      return topics.map((t) => _ReviewTopicGroup(
        topicNumber: t.index,
        title: t.displayTitle,
        cards: sortReviewCards(map[t.index] ?? []),
        imagePath: t.imagePath,
      )).toList();
    }, [topicsAsync, cardsAsync]);

    // 各グループの開始位置 (カバー+カード群)。ReviewCardsViewerPageの
    // flatItemsの並びと一致させ、タップしたカードへ直接ジャンプできるようにする。
    final groupStartIndex = useMemoized(() {
      final starts = <int>[];
      var idx = 0;
      for (final g in groups) {
        starts.add(idx);
        idx += g.cards.length + 1;
      }
      return starts;
    }, [groups]);

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value;
    Course? course;
    if (courses != null && lecture != null) {
      for (final c in courses) {
        if (c.id == lecture.courseId) {
          course = c;
          break;
        }
      }
    }

    final themeColor = course != null
        ? CourseStyleHelper.hexToColor(course.color, fallback: AppColors.deepGold)
        : AppColors.deepGold;

    final HSLColor hsl = HSLColor.fromColor(themeColor);
    final textThemeColor = hsl.lightness > 0.65 ? hsl.withLightness(0.5).toColor() : themeColor;

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              textThemeColor.withValues(alpha: 0.22),
              textThemeColor.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              CustomAppBar(
                showHomeButton: true,
                title: l10n.reviewCardsDashboardTitle,
                isLightBg: true,
              ),
              Expanded(
                child: _buildBody(context, ref, groups, groupStartIndex, courseId, textThemeColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<_ReviewTopicGroup> groups,
    List<int> groupStartIndex,
    String courseId,
    Color themeColor,
  ) {
    final cardsAsync = ref.watch(reviewCardsProvider(lectureId));

    if (cardsAsync.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold));
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined,
                size: 64, color: AppColors.paper.textPencil),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).reviewCardsDashboardGeneratingMessage,
              style:
                  TextStyle(color: AppColors.paper.textPencil, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 28),
      itemBuilder: (context, idx) {
        // ── Topic row ────────────────────────────────────────────────────
        final group = groups[idx];
        final groupStart = groupStartIndex[idx];
        final path = group.imagePath;
        final isAsset = path != null && path.startsWith('assets/');
        final imageFile = (path == null || isAsset)
            ? null
            : ref.watch(artifactFileProvider(path)).asData?.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.title,
              style: TextStyle(
                color: AppColors.paper.textInk,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 155,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: group.cards.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, tileIdx) {
                  if (tileIdx == 0) {
                    return GestureDetector(
                      onTap: () => context.push('${AppRoutes.coursesRootPath}/c/$courseId/rcv/$lectureId?index=$groupStart'),
                      child: SizedBox(
                        width: 115,
                        child: _CoverCardTile(
                          title: group.title,
                          imageFile: imageFile,
                          imagePath: path,
                        ),
                      ),
                    );
                  }
                  final card = group.cards[tileIdx - 1];
                  final preview = card.title?.trim().isNotEmpty == true
                      ? card.title!.trim()
                      : plainTextPreview(
                          card.cardContent.isNotEmpty
                              ? (card.cardContent.first.text ?? '')
                              : '');
                  return GestureDetector(
                    onTap: () => context.push('${AppRoutes.coursesRootPath}/c/$courseId/rcv/$lectureId?index=${groupStart + tileIdx}'),
                    child: Container(
                      width: 115,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(AppColors.paper.surface, themeColor, 0.1)!,
                            AppColors.paper.surface,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.black.withValues(alpha: 0.07)),
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
                            Text(
                              card.heroEmoji!.trim(),
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Flexible(
                            child: Text(
                              preview,
                              style: TextStyle(
                                color: AppColors.paper.textInk,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: card.heroEmoji?.trim().isNotEmpty == true ? 3 : 4,
                              overflow: TextOverflow.ellipsis,
                            ),
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
}

// ---------------------------------------------------------------------------
// Cover card thumbnail
// ---------------------------------------------------------------------------
class _CoverCardTile extends StatelessWidget {
  const _CoverCardTile({
    required this.title,
    required this.imageFile,
    this.imagePath,
  });

  final String title;
  final File? imageFile;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final bool isAsset = imagePath != null && imagePath!.startsWith('assets/');

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isAsset)
            Image.asset(imagePath!, fit: BoxFit.cover)
          else if (imageFile != null)
            Image.file(imageFile!, fit: BoxFit.cover)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: Colors.white.withValues(alpha: 0.75),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 2),
                    Shadow(color: Colors.white, blurRadius: 4),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
