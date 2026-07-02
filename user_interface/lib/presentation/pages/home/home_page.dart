import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/home_app_bar.dart';
import 'package:lecture_companion_ui/presentation/widgets/galaxy/galaxy_view.dart';

import 'widgets/announcement_bar.dart';
import 'widgets/recent_lectures_list.dart';
import 'widgets/bottom_control_bar.dart';
import 'widgets/combined_header.dart';

// 銀河ウィジェットの高さの、画面縦幅に対する割合
const double _kGalaxyHeightRatio = 0.25;
// FunFactsの高さ（固定）。
const double _kFunFactsHeight = 190.0;
// Coursesヘッダーの高さ（固定）。
const double _kCoursesHeaderHeight = 84.0;

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final scrollOffset = useState(0.0);
    final isTransitioning = useState(false);
    final showGradients = useState(true);
    
    // 銀河のジェスチャーを外部から制御するためのキー
    final galaxyKey = useMemoized(() => GlobalKey<GalaxyViewState>());

    // 銀河エリアに指が触れている間、外側のCustomScrollViewのスクロールを無効化する。
    // これがないと、縦方向のドラッグがジェスチャーアリーナで銀河のScaleGestureRecognizerと
    // Scrollableのドラッグ認識器の間で競合し、スクロール側が勝ってしまうことがある。
    final isGalaxyPointerDown = useState(false);

    // スクロール位置のリスナー
    useEffect(() {
      void listener() {
        if (scrollController.hasClients) {
          scrollOffset.value = scrollController.offset;
        }
      }
      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double navigationBarHeight = MediaQuery.of(context).padding.bottom;

    // 銀河ウィジェットの高さ（画面縦幅の1/4、端末サイズに応じて可変）
    final double galaxyHeight = screenHeight * _kGalaxyHeightRatio;

    // 各セクションの正確な高さを計算（スライド退避用）
    final double topAreaHeight = statusBarHeight + 56.0 + 68.0; // AppBar + AnnouncementBar
    final double bottomAreaHeight = 72.0 + navigationBarHeight + 16.0; // BottomControlBar (目安)

    // スクロール量に応じて銀河がぼける (スクロールした瞬間にリニアに開始)
    final double blurSigma = ((scrollOffset.value / galaxyHeight).clamp(0.0, 1.0) * 12.0);

    return PopScope(
      canPop: !isTransitioning.value,
      onPopInvokedWithResult: (didPop, result) {
        if (isTransitioning.value) {
          isTransitioning.value = false;
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: Stack(
          children: [
            // =============================================
            // 1. 最背面: 銀河 (遷移時に全画面へ拡大)
            // =============================================
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              top: isTransitioning.value ? 0.0 : topAreaHeight,
              left: 0,
              right: 0,
              height: isTransitioning.value ? screenHeight : galaxyHeight,
              child: Hero(
                tag: 'galaxy',
                child: GalaxyView(key: galaxyKey),
              ),
            ),

            // =============================================
            // 2. ブラーレイヤー (スクロール量に合わせて銀河をぼかす)
            // =============================================
            if (blurSigma > 0.1 && !isTransitioning.value)
              Positioned(
                top: topAreaHeight,
                left: 0,
                right: 0,
                height: galaxyHeight,
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: Container(color: Colors.black.withValues(alpha: 0.15)),
                    ),
                  ),
                ),
              ),

            // 銀河の上下のグラデーションフェード（境界線を滑らかにする）
            // 遷移時および戻り時のアニメーション中は非表示にし、すべてが元に戻った後にパッと表示する
            AnimatedOpacity(
              duration: Duration.zero,
              opacity: showGradients.value ? 1.0 : 0.0,
              child: Stack(
                children: [
                  // 上端のフェード
                  Positioned(
                    top: topAreaHeight,
                    left: 0,
                    right: 0,
                    height: 15,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.universe.voidBackground,
                              AppColors.universe.voidBackground.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 下端のフェード
                  Positioned(
                    top: topAreaHeight + galaxyHeight - 15,
                    left: 0,
                    right: 0,
                    height: 15,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.universe.voidBackground,
                              AppColors.universe.voidBackground.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // =============================================
            // 3. 前面スクロールエリア (遷移時は下にスライド&フェードアウト)
            // =============================================
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              top: isTransitioning.value ? screenHeight : topAreaHeight,
              bottom: isTransitioning.value ? -screenHeight : 0.0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: isTransitioning.value ? 0.0 : 1.0,
                child: CustomScrollView(
                  controller: scrollController,
                  physics: isGalaxyPointerDown.value
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  slivers: [
                    // 銀河の高さ分のスペーサー 兼 タッチイベント制御層
                    SliverToBoxAdapter(
                      child: Listener(
                        // pointerDown時点でスクロールを無効化しておくことで、
                        // その後のドラッグがジェスチャーアリーナで銀河側に確実に渡るようにする。
                        onPointerDown: (_) => isGalaxyPointerDown.value = true,
                        onPointerUp: (_) => isGalaxyPointerDown.value = false,
                        onPointerCancel: (_) => isGalaxyPointerDown.value = false,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: (d) => galaxyKey.currentState?.handleScaleStart(d),
                          onScaleUpdate: (d) => galaxyKey.currentState?.handleScaleUpdate(d),
                          onScaleEnd: (d) => galaxyKey.currentState?.handleScaleEnd(d),
                          onTap: isTransitioning.value
                              ? null
                              : () async {
                                  showGradients.value = false; // 遷移開始時に一瞬で非表示
                                  isTransitioning.value = true;

                                  // アニメーション時間 (600ms) を待ってからページ遷移
                                  await Future.delayed(const Duration(milliseconds: 600));
                                  if (context.mounted && isTransitioning.value) {
                                    // 戻り値を待って、戻ってきたら縮小アニメーションを開始する
                                    await context.push(AppRoutes.learningGalaxy);
                                    if (context.mounted) {
                                      isTransitioning.value = false;
                                      // 縮小アニメーション完了 (600ms) を待ってからパッと表示
                                      await Future.delayed(const Duration(milliseconds: 600));
                                      if (context.mounted && !isTransitioning.value) {
                                        showGradients.value = true;
                                      }
                                    }
                                  }
                                },
                          child: SizedBox(height: galaxyHeight),
                        ),
                      ),
                    ),
                    // FunFacts + Courses ヘッダー (銀河エリアを超えたら上端にSticky)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: CombinedHeaderDelegate(
                        funFactsHeight: _kFunFactsHeight,
                        coursesHeaderHeight: _kCoursesHeaderHeight,
                        scrollOffset: scrollOffset.value,
                      ),
                    ),
                    // 最近の講義リスト
                    const RecentLecturesList(),
                    // 下部余白（BottomControlBarを避けるための十分な高さ）
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 160),
                    ),
                  ],
                ),
              ),
            ),

            // =============================================
            // 4. 固定上部エリア (AppBar + Announcement, 遷移時は上に退避)
            // =============================================
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              top: isTransitioning.value ? -topAreaHeight : 0.0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: isTransitioning.value ? 0.0 : 1.0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HomeAppBar(),
                      const AnnouncementBar(),
                    ],
                  ),
                ),
              ),
            ),

            // =============================================
            // 5. 固定フッター (BottomControlBar, 遷移時は下に退避)
            // =============================================
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              bottom: isTransitioning.value ? -bottomAreaHeight : 0.0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: isTransitioning.value ? 0.0 : 1.0,
                child: const BottomControlBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
