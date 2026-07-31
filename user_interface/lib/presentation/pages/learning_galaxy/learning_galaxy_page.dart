import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
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

          // 2. 左上: SF HUD 戻るボタン ("<")
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: showOverlay.value ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0x990A0E1A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x334FA8FF)),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            } else {
                              context.pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. 前面: SF HUD オーバーレイ (下部に配置)
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