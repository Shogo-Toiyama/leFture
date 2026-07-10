import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/fun_fact/fun_fact_list_provider.dart';
import 'package:lecture_companion_ui/core/utils/text_preview.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class FunFactsCarousel extends ConsumerStatefulWidget {
  const FunFactsCarousel({super.key});

  @override
  ConsumerState<FunFactsCarousel> createState() => _FunFactsCarouselState();
}

class _FunFactsCarouselState extends ConsumerState<FunFactsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const carouselHeight = 160.0;
    final facts = ref.watch(recentFunFactsProvider).asData?.value ?? const <FunFact>[];
    final itemCount = facts.isEmpty ? 1 : facts.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: carouselHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: itemCount,
            physics: facts.isEmpty ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              if (facts.isEmpty) return const _DefaultFunFactCard();
              return _FunFactCard(fact: facts[index]);
            },
          ),
        ),
        if (facts.length > 1) ...[
          const SizedBox(height: 8),
          // インジケーター (.....)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              facts.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _currentPage
                      ? AppColors.starGold
                      : AppColors.universe.textComet.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class FunFactsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;

  FunFactsHeaderDelegate({this.height = 190.0});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // スクロール時に背景が少し暗く浮かび上がる演出（グラスモーフィズム調）
    final isPinned = shrinkOffset > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isPinned
            ? AppColors.universe.voidBackground.withValues(alpha: 0.8)
            : Colors.transparent,
      ),
      alignment: Alignment.center,
      height: height,
      child: const FunFactsCarousel(),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant FunFactsHeaderDelegate oldDelegate) {
    return oldDelegate.height != height;
  }
}

class _FunFactCard extends ConsumerWidget {
  final FunFact fact;
  const _FunFactCard({required this.fact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hook = fact.hook?.trim();
    final body = fact.body?.trim() ?? '';
    // Markdown記号やSID引用を除去したプレーンテキストでプレビュー表示する
    final mainText = plainTextPreview((hook != null && hook.isNotEmpty) ? '$hook $body' : body);

    // 講義一覧から該当の講義を取得
    final lectures = ref.watch(allLecturesStreamProvider).asData?.value ?? const [];
    final lecture = lectures.firstWhere(
      (l) => l.id == fact.lectureId,
      orElse: () => Lecture(
        id: '',
        userId: '',
        courseId: null,
        title: null,
        titleGenerated: null,
        sortOrder: 0,
        lectureDatetime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final lectureTitle = (lecture.id.isNotEmpty)
        ? (lecture.title?.trim().isNotEmpty == true
            ? lecture.title!
            : (lecture.titleGenerated?.trim().isNotEmpty == true
                ? lecture.titleGenerated!
                : 'Untitled Lecture'))
        : 'Unknown Lecture';

    return GestureDetector(
      // FunFactの元になった講義のビューワーへ飛ぶ (講義が特定できない場合はコース一覧へ)
      onTap: () => fact.lectureId != null
          ? context.go('${AppRoutes.notesRootPath}/c/${lecture.courseId}/v/${fact.lectureId}')
          : context.push(AppRoutes.notesRootPath),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 一番上の行にFunFactsのタイトルを表示
            if (fact.title?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  fact.title!.trim(),
                  style: TextStyle(
                    color: AppColors.starGold,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // 中部: Fact内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(
                  child: Text(
                    mainText,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            // 下部: メタデータ & リアクション
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lectureTitle,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _ReactionButton(
                    factId: fact.id,
                    reaction: 'like',
                    currentReaction: fact.metadata?['reaction'] as String?,
                  ),
                  const SizedBox(width: 8),
                  _ReactionButton(
                    factId: fact.id,
                    reaction: 'dislike',
                    currentReaction: fact.metadata?['reaction'] as String?,
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

class _ReactionButton extends ConsumerWidget {
  final String factId;
  final String reaction;
  final String? currentReaction;

  const _ReactionButton({
    required this.factId,
    required this.reaction,
    required this.currentReaction,
  });

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
      icon: Icon(iconData, color: iconColor, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () async {
        final newReaction = isActive ? null : reaction;
        try {
          await ref.read(funFactRepositoryProvider).updateReaction(factId, newReaction);
          // 状態をリフレッシュして再ロード
          ref.invalidate(recentFunFactsProvider);
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

/// FunFactがまだ1件も無い場合（レクチャーはあるがまだ解析が終わっていない等）に
/// 表示するデフォルトカード。文言は後で差し替え予定。
class _DefaultFunFactCard extends StatelessWidget {
  const _DefaultFunFactCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.notesRootPath),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    'Did you know? Quantum entanglement allows particles to affect each other instantly over any distance.',
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Intro to Physics',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
}
