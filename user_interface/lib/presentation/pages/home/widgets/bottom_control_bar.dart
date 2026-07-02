import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class BottomControlBar extends StatelessWidget {
  const BottomControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: 16.0,
            bottom: bottomPadding > 0 ? bottomPadding : 16.0,
          ),
          decoration: BoxDecoration(
            color: AppColors.universe.voidBackground.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 左: Study (Note)
              _BottomButton(
                icon: Icons.edit_note,
                label: 'Study',
                onTap: () {}, // context.push(AppRoutes.study)
              ),
    
              // 中央: Record (Big)
              GestureDetector(
                onTap: () => context.push(AppRoutes.recording),
                onLongPress: () {
                  // TODO: スライドしてNoteモードへ
                },
                child: Container(
                  width: 120,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.starGold,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                ),
              ),
    
              // 右: AI Chat
              _BottomButton(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                onTap: () => context.push(AppRoutes.aiChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.universe.glassWhiteLow,
              border: Border.all(color: AppColors.universe.glassBorder),
              borderRadius: BorderRadius.circular(20)
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          // Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}