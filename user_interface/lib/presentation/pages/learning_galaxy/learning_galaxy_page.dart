import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';


import 'package:lefture/application/galaxy/galaxy_state_provider.dart';

class LearningGalaxyPage extends HookConsumerWidget {
  const LearningGalaxyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOverlay = useState(false);

    useEffect(() {
      // 画面遷移完了後にHUDをフェードイン
      Future.delayed(const Duration(milliseconds: 300), () {
        showOverlay.value = true;
      });
      return null;
    }, []);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          // 1. 最背面: 引き継がれた3D銀河ビュー (全画面表示)
          const Positioned.fill(
            child: Hero(
              tag: 'galaxy',
              child: GalaxyView(),
            ),
          ),

          // 2. 前面: SF HUD オーバーレイ (下部に配置)
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 下部 HUD (カメラ操作、オートオービットトグル、ロードマップ起動)
                AnimatedSlide(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  offset: showOverlay.value ? Offset.zero : const Offset(0, 0.2),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: showOverlay.value ? 1.0 : 0.0,
                    child: SafeArea(
                      top: false,
                      child: _buildBottomHUD(context, ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // --- 下部 HUD 設計 ---
  Widget _buildBottomHUD(BuildContext context, WidgetRef ref) {
    final galaxyState = ref.watch(galaxyStateProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x990A0E1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x334FA8FF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 自動回転トグル
          _HUDButton(
            icon: galaxyState.autoRotate ? Icons.sync : Icons.sync_disabled,
            label: 'AUTO ORBIT',
            isActive: galaxyState.autoRotate,
            onTap: () {
              ref.read(galaxyStateProvider.notifier).toggleAutoRotate();
            },
          ),

          // 知識ノード (ロードマップ) の起動ボタン
          GestureDetector(
            onTap: () => _showRoadmapBottomSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.starGold,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.starGold.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.bubble_chart, color: Colors.black, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'KNOWLEDGE NODES',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // カメラリセット
          _HUDButton(
            icon: Icons.center_focus_strong,
            label: 'RESET CAM',
            isActive: false,
            onTap: () {
              ref.read(galaxyStateProvider.notifier).resetCamera();
            },
          ),
        ],
      ),
    );
  }

  // --- ロードマップのボトムシート起動 ---
  void _showRoadmapBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: const Color(0xFA050914), // 高透明度な暗青黒
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border.all(
              color: const Color(0x404FA8FF), // ネオンブルー境界線
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // ドラッグハンドル
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // タイトル部
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KNOWLEDGE ROADMAP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SECTOR PROGRESS: 2 / 4 COMPLETED',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white12, thickness: 1),
              const SizedBox(height: 16),
              // ロードマップの内容を表示
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      _buildGalaxyNode(Icons.school_outlined, 'Introduction to CS', true),
                      _buildLine(true),
                      _buildGalaxyNode(Icons.code_outlined, 'Variables & Types', true),
                      _buildLine(true),
                      _buildGalaxyNode(Icons.loop_outlined, 'Control Flow & Logic', false),
                      _buildLine(false),
                      _buildGalaxyNode(Icons.storage_outlined, 'Arrays & Lists', false),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGalaxyNode(IconData icon, String label, bool isCompleted) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? AppColors.starGold
                : AppColors.universe.glassWhiteLow,
            border: Border.all(
              color: isCompleted ? Colors.white : AppColors.universe.glassBorder,
              width: 1.5,
            ),
            boxShadow: isCompleted
                ? [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Icon(
            icon,
            color: isCompleted ? Colors.black : Colors.white70,
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildLine(bool isCompleted) {
    return Container(
      width: 2,
      height: 35,
      color: isCompleted ? AppColors.starGold : Colors.white12,
      margin: const EdgeInsets.symmetric(vertical: 4),
    );
  }
}

// --- HUD用 ボタンコンポーネント ---
class _HUDButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _HUDButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0x334FA8FF) // アクティブ時はネオンブルー
                  : const Color(0x1AFFFFFF),
              border: Border.all(
                color: isActive ? const Color(0xFF4FA8FF) : Colors.white24,
                width: 1.0,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF4FA8FF) : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}