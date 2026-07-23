import 'dart:ui';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/announcement/announcement_provider.dart';
import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/credit/credit_providers.dart';
import 'package:lecture_companion_ui/application/fun_fact/fun_fact_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/debug/debug_providers.dart';
import 'package:lecture_companion_ui/application/profile/user_profile_provider.dart';
import 'package:lecture_companion_ui/application/recording/recording_language_controller.dart';
import 'package:lecture_companion_ui/core/services/recording_preferences.dart';
import 'package:lecture_companion_ui/core/utils/connectivity_utils.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';
import 'package:lecture_companion_ui/presentation/widgets/galaxy/galaxy_view.dart';
import 'package:lecture_companion_ui/presentation/widgets/spaceship_announcement_modal.dart';

import 'widgets/announcement_bar.dart';
import 'widgets/recent_lectures_list.dart';
import 'widgets/combined_header.dart';
import 'widgets/empty_home_content.dart';

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

    // アプリ起動時（Home初回表示時）に、Supabase上のレクチャーをローカルDBへ同期する。
    // 頻度は LectureController 側の interval（デフォルト15分）でレート制限される。
    useEffect(() {
      ref.read(lectureControllerProvider.notifier).bootstrapIfNeeded();
      return null;
    }, const []);

    // Realtime Recordingが有効な場合、Homeに来るたびに現在のRecording Language
    // のオンデバイスASRモデルが揃っているか確認し、無ければ黙ってダウンロードを
    // 開始する(失敗してもダイアログは出さない。未準備の状態は言語ピッカーの
    // アイコンで分かるようにする)。
    useEffect(() {
      if (RecordingPreferences().getRealtimeTranscribe()) {
        final lang = ref.read(recordingLanguageControllerProvider);
        ref.read(asrModelManagerProvider.notifier).ensureModelReady(lang);
      }
      return null;
    }, const []);

    // Home表示時に宇宙船風お知らせモーダルを表示（毎回テスト表示）
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showSpaceshipAnnouncementModal(context);
      });
      return null;
    }, const []);

    // プランに一度も加入していないユーザーは、通常のダッシュボードより先に
    // クレジットページへ誘導する。hasActivePlanが変化した時だけ発火するので、
    // 毎rebuildで無限にpushされることはない。
    final creditSummary = ref.watch(creditSummaryProvider).asData?.value;
    useEffect(() {
      if (creditSummary != null && !creditSummary.hasActivePlan) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.push(AppRoutes.creditDetail);
          }
        });
      }
      return null;
    }, [creditSummary?.hasActivePlan]);

    // コースが1件も無い、もしくはコースはあってもレクチャーが1件も無いユーザーには、
    // 通常のダッシュボードの代わりにオンボーディング用の空状態画面を表示する。
    // （コースがあってもレクチャーが無ければ、RecentLecturesList等はどのみち空になるため）
    final courses = ref.watch(courseListProvider).asData?.value;
    final lectures = ref.watch(allLecturesStreamProvider).asData?.value;
    final forceEmpty = ref.watch(debugForceEmptyHomeProvider);

    // データ読み込み中は、一瞬のチラつきを防ぐためにローディング画面を表示する
    if (courses == null || lectures == null) {
      return Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.starGold),
          ),
        ),
      );
    }

    if (lectures.isEmpty || forceEmpty) {
      return const EmptyHomeContent();
    }

    // 銀河エリアを引っ張って離すとリロードする（下に表示されるレクチャー等の実データを再取得する）
    Future<void> handleRefresh() async {
      // オフライン時はネットワーク処理を試みない(タイムアウトが発火するまで
      // スピナーが固まって見える不具合を避けるため)。ローカルキャッシュは
      // 既に表示されているので、ここでは通知だけする。
      if (!await isDeviceOnline()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're offline. Showing cached data.")),
          );
        }
        return;
      }

      await ref.read(lectureControllerProvider.notifier).bootstrapLectures();
      ref.invalidate(courseListProvider);
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(recentFunFactsProvider);
      ref.invalidate(latestAnnouncementProvider);
    }

    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double navigationBarHeight = MediaQuery.of(context).padding.bottom;

    // 銀河ウィジェットの高さ（画面縦幅の1/4、端末サイズに応じて可変）
    final double galaxyHeight = screenHeight * _kGalaxyHeightRatio;

    // 各セクションの正確な高さを計算（スライド退避用）
    final double topAreaHeight = statusBarHeight + 56.0 + 68.0; // AppBar + AnnouncementBar

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
                    // Pull-to-refresh: スクロールが一番上（銀河が全部見えている状態）の時だけ、
                    // さらに下に引っ張るとこのControlがオーバースクロールを検知してリロードする。
                    // 銀河エリア自体は独自のGestureDetectorでスケール/回転を処理して
                    // スクロール判定を無効化するため、銀河の下（FunFacts/Courses/レクチャー欄）
                    // から指を離さずに引っ張った場合のみ発火する。
                    CupertinoSliverRefreshControl(
                      onRefresh: handleRefresh,
                    ),
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
                    // 下部余白（FABを避けるための高さ）
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 100),
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
                      const CustomAppBar(),
                      const AnnouncementBar(),
                    ],
                  ),
                ),
              ),
            ),

            // =============================================
            // 5. 固定フッター (Floating Recording Button, 遷移時は下に退避)
            // =============================================
            AnimatedPositioned(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              bottom: isTransitioning.value ? -80.0 : (16.0 + navigationBarHeight),
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: isTransitioning.value ? 0.0 : 1.0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.recording),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.starGold.withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Record Lecture',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
