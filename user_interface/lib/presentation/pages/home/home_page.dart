import 'dart:ui';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/announcement/announcement_provider.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/fun_fact/fun_fact_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/application/debug/debug_providers.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';
import 'package:lefture/presentation/widgets/spaceship_announcement_modal.dart';
import 'package:lefture/application/transmission/transmission_provider.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

import 'widgets/announcement_bar.dart';
import 'widgets/recent_lectures_list.dart';
import 'widgets/combined_header.dart';
import 'widgets/empty_home_content.dart';
import 'widgets/initial_sync_error_content.dart';

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
    final l10n = AppLocalizations.of(context);
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
    // 完了をsyncAttempted経由で追跡する。これが無いと、新規インストール直後
    // (ローカルDBがまだ空)にこの同期がawaitされないまま下のcourses/lectures
    // watchが「ローカルDBは空」を即座に返し、「本当に0件」と誤認して
    // EmptyHomeContentへ飛んでしまう(実際にはクラウドにレクチャーがあっても)。
    final syncAttempted = useState(false);
    // 'lecture'の全件Pullが過去に一度でも成功した実績があるか。falseのまま
    // 残るのは、このエフェクトがbootstrapを試みた後もその実績が無い場合のみ
    // ——「本当に0件」なのか「一度もPullできていないだけ」なのかの区別に使う
    // (判定不能時はエラー画面を誤って出さないよう安全側のtrueにしておく)。
    final hasSyncedBefore = useState(true);
    useEffect(() {
      () async {
        DevLog.add('🏠 [HomePage] bootstrapIfNeeded effect START');
        try {
          await ref
              .read(lectureControllerProvider.notifier)
              .bootstrapIfNeeded();
          ref.invalidate(courseListProvider);
          DevLog.add('🏠 [HomePage] bootstrapIfNeeded OK & courseListProvider refreshed');
        } catch (e, st) {
          DevLog.add('🏠 [HomePage] bootstrapIfNeeded ERROR: $e\n$st');
        } finally {
          try {
            hasSyncedBefore.value = await ref
                .read(lectureControllerProvider.notifier)
                .hasEverSyncedLectures();
          } catch (e, st) {
            DevLog.add('🏠 [HomePage] hasEverSyncedLectures ERROR: $e\n$st');
            hasSyncedBefore.value = true;
          }
          syncAttempted.value = true;
          DevLog.add(
            '🏠 [HomePage] syncAttempted=TRUE, hasSyncedBefore=${hasSyncedBefore.value}',
          );
        }
      }();
      return null;
    }, const []);

    // Homeに来るたびにクレジット残量を自動で再取得する(録音・解析の後に
    // Homeへ戻ってきた時に古い値のままにならないようにするため)。
    // ref.invalidateはInheritedWidget(ProviderScope)の検索を伴うため、
    // useEffect内(HookState.initHook相当)で同期的に呼ぶとFlutterの
    // 「initState中にdependOnInheritedWidgetOfExactTypeは呼べない」制約に
    // 引っかかる。1フレーム後(addPostFrameCallback)まで遅らせて回避する。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(creditSummaryProvider);
      });
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

    // 未読のお知らせ（AppTransmission）が存在する場合のみ、宇宙船モーダルを自動ポップアップ
    // ただし、オンボーディング未完了（ユーザー登録直後など）の場合は表示をスキップしユーザーを圧倒させない
    final unreadTransmissionsAsync = ref.watch(unreadTransmissionsProvider);
    useEffect(() {
      final unreadList = unreadTransmissionsAsync.asData?.value;
      DevLog.add(
        '🏠 [HomePage] unreadTransmissionsAsync isLoading=${unreadTransmissionsAsync.isLoading}, count=${unreadList?.length}',
      );
      if (unreadList != null && unreadList.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!context.mounted) return;
          final hasCompleted =
              await ref.read(userProfileRepositoryProvider).hasCompletedOnboarding();
          if (!hasCompleted || !context.mounted) return;

          DevLog.add('🏠 [HomePage] Showing Spaceship Announcement Modal...');
          final items = unreadList
              .map((t) => SpaceshipAnnouncementItem.fromTransmission(t))
              .toList();
          await showSpaceshipAnnouncementModal(context, announcements: items);
          DevLog.add('🏠 [HomePage] Spaceship Announcement Modal closed');
          if (context.mounted) {
            await markTransmissionsAsRead(ref, unreadList);
          }
        });
      }
      return null;
    }, [unreadTransmissionsAsync.asData?.value]);

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
    final coursesAsync = ref.watch(courseListProvider);
    final lecturesAsync = ref.watch(allLecturesStreamProvider);
    // .asDataだとCourse作成後のref.invalidate(courseListProvider)で
    // 再取得中(AsyncLoading)の間ずっとnullになり、ホーム全体がローディング
    // 画面(ほぼ黒背景)に差し替わってしまう。.valueは再取得中でも直前の値を
    // 保持し続けるため、チラつき/暗転を防げる。
    final courses = coursesAsync.value;
    final lectures = lecturesAsync.value;
    final forceEmpty = ref.watch(debugForceEmptyHomeProvider);

    // 初回の必須Pullが失敗した状態(InitialSyncErrorContent)からの再試行。
    // オフラインなら試みずSnackBarのみ出す(Pull-to-Refreshと同じ方針)。
    Future<void> handleInitialSyncRetry() async {
      if (!await isDeviceOnline()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.homeOfflineSnackBarMessage)),
          );
        }
        return;
      }
      await ref.read(lectureControllerProvider.notifier).bootstrapLectures(reason: 'home_initial_sync_retry');
      hasSyncedBefore.value = await ref
          .read(lectureControllerProvider.notifier)
          .hasEverSyncedLectures();
      ref.invalidate(courseListProvider);
      ref.invalidate(currentUserProfileProvider);
    }

    // DevLog.add(
    //   '🏠 [HomePage] build state: '
    //   'coursesAsync(isLoading=${coursesAsync.isLoading}, hasError=${coursesAsync.hasError}, err=${coursesAsync.error}), '
    //   'lecturesAsync(isLoading=${lecturesAsync.isLoading}, hasError=${lecturesAsync.hasError}, err=${lecturesAsync.error}), '
    //   'coursesCount=${courses?.length}, '
    //   'lecturesCount=${lectures?.length}, '
    //   'syncAttempted=${syncAttempted.value}',
    // );

    // データ読み込み中は、一瞬のチラつきを防ぐためにローディング画面を表示する。
    // lecturesが0件の場合は、上の同期(syncAttempted)が一度終わるまでは
    // 「まだ同期前で空」の可能性があるため、ローディング扱いのままにする
    // (新規インストール直後に本当はレクチャーがあるのにEmptyHomeContentへ
    // 飛んでしまう不具合の対策)。
    final stillWaitingForFirstSync =
        lectures != null && lectures.isEmpty && !syncAttempted.value;
    if (courses == null || lectures == null || stillWaitingForFirstSync) {
      DevLog.add(
        '🏠 [HomePage] Showing CircularProgressIndicator (loading): '
        'coursesNull=${courses == null}, lecturesNull=${lectures == null}, stillWaiting=$stillWaitingForFirstSync',
      );
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
      // forceEmptyはQAトグルなので常にEmptyHomeContentを優先する。
      // hasSyncedBefore==falseは「一度も'lecture'の全件Pullに成功していない」
      // ことを意味し、この場合の「0件」は本当に0件なのか単に未同期なのか
      // 区別できないため、紛らわしいEmptyHomeContentではなく明示的な
      // エラー画面(再試行ボタン付き)を出す。
      if (!forceEmpty && !hasSyncedBefore.value) {
        return InitialSyncErrorContent(onRetry: handleInitialSyncRetry);
      }
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
            SnackBar(content: Text(l10n.homeOfflineSnackBarMessage)),
          );
        }
        return;
      }

      await ref.read(lectureControllerProvider.notifier).bootstrapLectures(reason: 'home_pull_to_refresh');
      ref.invalidate(courseListProvider);
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(recentFunFactsProvider);
      ref.invalidate(latestAnnouncementProvider);
      ref.invalidate(creditSummaryProvider);
    }

    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double navigationBarHeight = MediaQuery.of(context).padding.bottom;

    // 銀河ウィジェットの高さ（画面縦幅の1/4、端末サイズに応じて可変）
    final double galaxyHeight = screenHeight * _kGalaxyHeightRatio;

    // 各セクションの正確な高さを計算（スライド退避用）
    final double topAreaHeight =
        statusBarHeight + 56.0 + 68.0; // AppBar + AnnouncementBar

    // スクロール量に応じて銀河がぼける (スクロールした瞬間にリニアに開始)
    final double blurSigma =
        ((scrollOffset.value / galaxyHeight).clamp(0.0, 1.0) * 12.0);

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
                      filter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.15),
                      ),
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
                              AppColors.universe.voidBackground.withValues(
                                alpha: 0.0,
                              ),
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
                              AppColors.universe.voidBackground.withValues(
                                alpha: 0.0,
                              ),
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
                    CupertinoSliverRefreshControl(onRefresh: handleRefresh),
                    // 銀河の高さ分のスペーサー 兼 タッチイベント制御層
                    SliverToBoxAdapter(
                      child: Listener(
                        // pointerDown時点でスクロールを無効化しておくことで、
                        // その後のドラッグがジェスチャーアリーナで銀河側に確実に渡るようにする。
                        onPointerDown: (_) => isGalaxyPointerDown.value = true,
                        onPointerUp: (_) => isGalaxyPointerDown.value = false,
                        onPointerCancel: (_) =>
                            isGalaxyPointerDown.value = false,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: (d) =>
                              galaxyKey.currentState?.handleScaleStart(d),
                          onScaleUpdate: (d) =>
                              galaxyKey.currentState?.handleScaleUpdate(d),
                          onScaleEnd: (d) =>
                              galaxyKey.currentState?.handleScaleEnd(d),
                          onTap: isTransitioning.value
                              ? null
                              : () async {
                                  showGradients.value = false; // 遷移開始時に一瞬で非表示
                                  isTransitioning.value = true;

                                  // アニメーション時間 (600ms) を待ってからページ遷移
                                  await Future.delayed(
                                    const Duration(milliseconds: 600),
                                  );
                                  if (context.mounted &&
                                      isTransitioning.value) {
                                    // 戻り値を待って、戻ってきたら縮小アニメーションを開始する
                                    await context.push(
                                      AppRoutes.learningGalaxy,
                                    );
                                    if (context.mounted) {
                                      isTransitioning.value = false;
                                      // 縮小アニメーション完了 (600ms) を待ってからパッと表示
                                      await Future.delayed(
                                        const Duration(milliseconds: 600),
                                      );
                                      if (context.mounted &&
                                          !isTransitioning.value) {
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
                    Builder(
                      builder: (context) {
                        final textScaler = MediaQuery.textScalerOf(context);
                        final dynamicCoursesHeight = (textScaler.scale(20) + textScaler.scale(12) + 48.0).clamp(_kCoursesHeaderHeight, 150.0);
                        final dynamicFunFactsHeight = (textScaler.scale(160) + 30.0).clamp(_kFunFactsHeight, 260.0);
                        return SliverPersistentHeader(
                          pinned: true,
                          delegate: CombinedHeaderDelegate(
                            funFactsHeight: dynamicFunFactsHeight,
                            coursesHeaderHeight: dynamicCoursesHeight,
                            scrollOffset: scrollOffset.value,
                          ),
                        );
                      },
                    ),
                    // 最近の講義リスト
                    const RecentLecturesList(),
                    // 下部余白（FABを避けるための高さ）
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
                    children: [const CustomAppBar(), const AnnouncementBar()],
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
              bottom: isTransitioning.value
                  ? -80.0
                  : (16.0 + navigationBarHeight),
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: isTransitioning.value ? 0.0 : 1.0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.recording),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.homeRecordLectureButton,
                            style: const TextStyle(
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
