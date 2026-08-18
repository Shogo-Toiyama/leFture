import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// トピック一覧ボトムシートを表示するヘルパー関数
Future<void> showTopicsSheet({
  required BuildContext context,
  required String lectureId,
  String? courseId,
  List<LectureTopic>? initialTopics,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TopicsSheet(
      lectureId: lectureId,
      courseId: courseId,
      initialTopics: initialTopics,
    ),
  );
}

/// 講義のトピック一覧を表示するボトムシート
class TopicsSheet extends ConsumerWidget {
  const TopicsSheet({
    super.key,
    required this.lectureId,
    this.courseId,
    this.initialTopics,
  });

  final String lectureId;
  final String? courseId;
  final List<LectureTopic>? initialTopics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final cardsAsync = ref.watch(reviewCardsProvider(lectureId));

    final topics = topicsAsync.asData?.value ?? initialTopics ?? const <LectureTopic>[];
    final allCards = cardsAsync.asData?.value ?? const <ReviewCard>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
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
              // ドラッグハンドルバー
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // シートヘッダー
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        topics.isNotEmpty
                            ? '${l10n.lectureViewerTopicsSheetTitle} (${topics.length})'
                            : l10n.lectureViewerTopicsSheetTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: AppColors.universe.textComet,
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // トピック一覧
              Expanded(
                child: topics.isEmpty
                    ? Center(
                        child: Text(
                          l10n.lectureViewerTopicEmptyState,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 15,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: topics.length,
                        separatorBuilder: (context, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final topic = topics[index];
                          return _TopicTile(
                            key: ValueKey(topic.id),
                            topic: topic,
                            topicIndex: index,
                            lectureId: lectureId,
                            courseId: courseId,
                            allCards: allCards,
                            allTopics: topics,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopicTile extends ConsumerWidget {
  const _TopicTile({
    super.key,
    required this.topic,
    required this.topicIndex,
    required this.lectureId,
    this.courseId,
    required this.allCards,
    required this.allTopics,
  });

  final LectureTopic topic;
  final int topicIndex;
  final String lectureId;
  final String? courseId;
  final List<ReviewCard> allCards;
  final List<LectureTopic> allTopics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasSummary = topic.summary?.trim().isNotEmpty == true;

    // このトピックに属するカードの枚数と、全カードリストにおける先頭インデックスを計算
    final topicCards = allCards.where((c) => c.topicNumber == topic.index).toList();
    final hasReviewCards = topicCards.isNotEmpty;

    int firstCardIndex = 0;
    if (hasReviewCards) {
      final sortedCardsMap = <int, List<ReviewCard>>{};
      for (final c in allCards) {
        sortedCardsMap.putIfAbsent(c.topicNumber, () => []).add(c);
      }
      for (final t in allTopics) {
        if (t.index == topic.index) break;
        // 各トピックには 表紙カード(1枚) + コンテンツカード(cards.length) が存在するため 1 + length で加算
        firstCardIndex += 1 + (sortedCardsMap[t.index]?.length ?? 0);
      }
    }

    final effectiveCourseId = courseId ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.universe.glassBorder,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上部: サムネイル画像 + タイトル・サマリー
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // トピック画像
              _TopicThumbnail(imagePath: topic.imagePath),
              const SizedBox(width: 14),
              // タイトル & サマリー
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // トピック番号ラベル
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.starGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TOPIC ${topic.index}',
                        style: TextStyle(
                          color: AppColors.starGold,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // トピックタイトル
                    Text(
                      topic.displayTitle,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    if (hasSummary) ...[
                      const SizedBox(height: 6),
                      Text(
                        topic.summary!,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 境界ライン
          Divider(
            color: AppColors.universe.glassBorder.withValues(alpha: 0.5),
            height: 1,
          ),
          const SizedBox(height: 10),
          // 下部: アクションボタン（Review Cards / Deep Notes）
          // 文字拡大時にもオーバーフローしないよう Wrap を採用
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 復習カードボタン
              _TopicActionButton(
                icon: Icons.style_outlined,
                label: l10n.lectureViewerTopicCardReviewCards,
                accentColor: AppColors.starGold,
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(
                    '${AppRoutes.coursesRootPath}/c/$effectiveCourseId/rcv/$lectureId?index=$firstCardIndex',
                  );
                },
              ),
              // 詳細ノートボタン
              _TopicActionButton(
                icon: Icons.description_outlined,
                label: l10n.lectureViewerTopicCardDeepNotes,
                accentColor: const Color(0xFF64B5F6),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(
                    '${AppRoutes.coursesRootPath}/c/$effectiveCourseId/dnd/$lectureId/$topicIndex',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// トピックサムネイル画像ウィジェット
class _TopicThumbnail extends ConsumerWidget {
  const _TopicThumbnail({required this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const double size = 72.0;

    if (imagePath == null || imagePath!.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Icon(
          Icons.hub_outlined,
          color: AppColors.universe.textComet,
          size: 28,
        ),
      );
    }

    final path = imagePath!;
    final Widget imageWidget;

    if (path.startsWith('assets/')) {
      imageWidget = Image.asset(
        path,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _fallbackPlaceholder(size),
      );
    } else {
      final fileAsync = ref.watch(artifactFileProvider(path));
      final File? file = fileAsync.asData?.value;

      if (file != null && file.existsSync()) {
        imageWidget = Image.file(
          file,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _fallbackPlaceholder(size),
        );
      } else {
        imageWidget = Container(
          width: size,
          height: size,
          color: AppColors.universe.glassWhiteLow,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            ),
          ),
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: imageWidget,
      ),
    );
  }

  Widget _fallbackPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.universe.glassWhiteLow,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.universe.textComet,
        size: 24,
      ),
    );
  }
}

/// トピックカード下部のアクションボタン
class _TopicActionButton extends StatelessWidget {
  const _TopicActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: accentColor,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: accentColor.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
