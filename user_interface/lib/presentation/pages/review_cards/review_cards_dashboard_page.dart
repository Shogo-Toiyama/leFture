// lib/presentation/pages/review_cards/review_cards_dashboard_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/core/utils/text_preview.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';


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

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(
              showHomeButton: true,
              title: 'Review Cards',
              isLightBg: true,
            ),
            Expanded(
              child: _buildBody(context, ref, groups, groupStartIndex, courseId),
            ),
          ],
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
              'Review cards are being generated…',
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
        final imageFile = group.imagePath == null
            ? null
            : ref
                .watch(artifactFileProvider(group.imagePath!))
                .asData
                ?.value;

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
                      onTap: () => context.push('${AppRoutes.notesRootPath}/c/$courseId/rcv/$lectureId?index=$groupStart'),
                      child: SizedBox(
                        width: 115,
                        child:
                            _CoverCardTile(title: group.title, imageFile: imageFile),
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
                    onTap: () => context.push('${AppRoutes.notesRootPath}/c/$courseId/rcv/$lectureId?index=${groupStart + tileIdx}'),
                    child: Container(
                      width: 115,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.paper.surface,
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
                            Text(card.heroEmoji!.trim(),
                                style: const TextStyle(fontSize: 26)),
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
}

// ---------------------------------------------------------------------------
// Cover card thumbnail
// ---------------------------------------------------------------------------
class _CoverCardTile extends StatelessWidget {
  const _CoverCardTile({required this.title, required this.imageFile});

  final String title;
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageFile != null)
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
