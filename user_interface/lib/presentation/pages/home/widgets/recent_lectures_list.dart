import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class RecentLecturesList extends HookConsumerWidget {
  const RecentLecturesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTopVisible = useState(false);
    final isBottomVisible = useState(true);

    return Column(
      children: [
        // ヘッダー部分（固定）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT LECTURES',
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
              InkWell(
                onTap: () => context.push(AppRoutes.notesRoot),
                child: Row(
                  children: [
                    Text('View All', style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, color: Colors.white54, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // リスト部分（ここだけスクロールする）
        Expanded(
          child: Stack(
            children: [
              // 1. スクロールを監視するラッパー
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // スクロール量の変化（Metrics）をチェック
                  if (notification is ScrollUpdateNotification || notification is ScrollMetricsNotification) {
                    final metrics = notification.metrics;
                    
                    // 上端にいるか？ (0より大きければ、上への余地がある = グラデ表示)
                    final canScrollUp = metrics.pixels > 0;
                    if (isTopVisible.value != canScrollUp) {
                      isTopVisible.value = canScrollUp;
                    }

                    // 下端にいるか？ (最大値より小さければ、下への余地がある = グラデ表示)
                    // ※ maxScrollExtentが0（リストが短い）場合は表示しない
                    final canScrollDown = metrics.maxScrollExtent > 0 && metrics.pixels < metrics.maxScrollExtent;
                    if (isBottomVisible.value != canScrollDown) {
                      isBottomVisible.value = canScrollDown;
                    }
                  }
                  return false; // イベントを止めずに他へ流す
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), // 下に少し余白
                  itemCount: 10, 
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _LectureCard(index: index);
                  },
                ),
              ),

              // 2. 上のグラデーション (IgnorePointerでタッチ透過)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 40,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isTopVisible.value ? 1.0 : 0.0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.universe.voidBackground, // 宇宙の黒
                            AppColors.universe.voidBackground.withValues(alpha: 0.0), // 透明
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 3. 下のグラデーション
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 60, // 下は少し広めに
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isBottomVisible.value ? 1.0 : 0.0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.universe.voidBackground, // 宇宙の黒
                            AppColors.universe.voidBackground.withValues(alpha: 0.0), // 透明
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
      ],
    );
  }
}

class _LectureCard extends StatelessWidget {
  final int index;
  const _LectureCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.universe.glassWhiteHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined, color: AppColors.starGold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Introduction to Computer Science - Week $index',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: AppColors.universe.textComet),
                    const SizedBox(width: 4),
                    Text(
                      '2 hours ago',
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_outline, color: Colors.white30, size: 28),
        ],
      ),
    );
  }
}