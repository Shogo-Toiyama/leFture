import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/connectivity/connectivity_status_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// アプリ全体共通で、オフライン中は画面下部に「You're offline」を表示する。
/// [child]の上にStackで重ねるだけで、個々のページ側の改修は不要。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 接続状態が判明するまで(初回のみ)はバナーを出さない(trueをデフォルトに)。
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;

    return Stack(
      children: [
        child,
        if (!isOnline)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                child: Container(
                  width: double.infinity,
                  color: AppColors.correctionRed,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "You're offline",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
