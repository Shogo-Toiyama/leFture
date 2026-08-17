import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/fun_fact/fun_fact_list_provider.dart';
import 'package:lefture/core/utils/text_preview.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/fun_fact.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/glowing_rainbow_border.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

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
          // 宇宙船風アニメーション付き軌道ドットインジケーター
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              facts.length,
              (index) {
                final isSelected = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 20.0 : 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: isSelected
                        ? AppColors.starGold
                        : AppColors.universe.textComet.withValues(alpha: 0.4),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.starGold.withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : [],
                  ),
                );
              },
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

    final l10n = AppLocalizations.of(context);
    final lectureTitle = (lecture.id.isNotEmpty)
        ? (lecture.title?.trim().isNotEmpty == true
            ? lecture.title!
            : (lecture.titleGenerated?.trim().isNotEmpty == true
                ? lecture.titleGenerated!
                : l10n.funFactsUntitledLecture))
        : l10n.funFactsUnknownLecture;

    return GestureDetector(
      // FunFactの元になった講義のビューワーへ飛ぶ (講義が特定できない場合はコース一覧へ)
      onTap: () => fact.lectureId != null
          ? context.push(
              '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/v/${fact.lectureId}?scrollTo=fun_fact',
            )
          : context.push(AppRoutes.coursesRootPath),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GlowingRainbowBorder(
          borderRadius: 20.0,
          borderWidth: 1.5,
          glowRadius: 6.0,
          animate: true,
          innerGlow: true,
          glowOpacity: 0.2,
          child: Container(
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
                        currentReaction: fact.reaction,
                      ),
                      const SizedBox(width: 8),
                      _ReactionButton(
                        factId: fact.id,
                        reaction: 'dislike',
                        currentReaction: fact.reaction,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                AppLocalizations.of(context).funFactsUpdateReactionFailed(e.toString()),
              ),
            ),
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
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => context.push(AppRoutes.coursesRootPath),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GlowingRainbowBorder(
          borderRadius: 20.0,
          borderWidth: 1.5,
          glowRadius: 6.0,
          animate: true,
          innerGlow: true,
          glowOpacity: 0.2,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.universe.glassWhiteLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.universe.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 一番上の行にタイトルを表示
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    l10n.funFactsDefaultCardTitle,
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
                        l10n.funFactsDefaultCardBody,
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
                // 下部: メタデータ
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
                          l10n.funFactsDefaultCardFooter,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
