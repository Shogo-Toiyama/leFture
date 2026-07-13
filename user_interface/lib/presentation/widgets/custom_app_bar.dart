import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'recording_timer_chip.dart';

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({
    super.key,
    this.showHomeButton = false,
    this.title,
    this.isLightBg = false,
    this.actions,
  });

  final bool showHomeButton;
  final String? title;
  final bool isLightBg;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final textColor = isLightBg ? AppColors.paper.textInk : AppColors.universe.textStarlight;
    final iconColor = isLightBg ? AppColors.paper.textInk : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 左側と右側の要素
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左: ホームボタン + 録音チップ (リアルタイムで同期)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHomeButton) ...[
                    IconButton(
                      icon: Icon(Icons.home, color: iconColor),
                      onPressed: () => context.go(AppRoutes.home),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const RecordingTimerChip(),
                ],
              ),

              // 右: プロフィール & クレジット残量 (および追加アクションボタン)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actions != null) ...[
                    ...actions!,
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.profile),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // クレジット残量ゲージ
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            value: 0.7, // Fake: 残り70%
                            strokeWidth: 3,
                            backgroundColor: isLightBg 
                                ? AppColors.paper.textInk.withValues(alpha: 0.1)
                                : AppColors.universe.glassWhiteLow,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLightBg ? AppColors.deepGold : AppColors.starGold,
                            ),
                          ),
                        ),
                        // アイコン本体
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLightBg ? AppColors.paper.textInk.withValues(alpha: 0.1) : Colors.white,
                          ),
                          child: Icon(
                            Icons.person,
                            color: isLightBg ? AppColors.paper.textInk : Colors.grey,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            ],
          ),

          // 中央タイトル (もし指定されている場合)
          if (title != null)
            IgnorePointer(
              child: Center(
                child: Text(
                  title!,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
