import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 初回の必須Pull（オンボーディング直後など、ローカルDBにまだ何のフォール
/// バック先も無い状態）がオフライン等で完了できなかった場合に、
/// EmptyHomeContentの代わりに表示するフルスクリーンのエラー画面。
///
/// EmptyHomeContentと違い「本当に0件かどうか」は不明なため、チェックリスト
/// ではなく「サーバーに接続できなかった」ことを明示し、再試行を促す。
class InitialSyncErrorContent extends StatefulWidget {
  const InitialSyncErrorContent({super.key, required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<InitialSyncErrorContent> createState() =>
      _InitialSyncErrorContentState();
}

class _InitialSyncErrorContentState extends State<InitialSyncErrorContent> {
  bool _retrying = false;

  Future<void> _handleRetry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        color: AppColors.correctionRed,
                        size: 56,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.initialSyncErrorTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.initialSyncErrorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: _retrying ? null : _handleRetry,
                        icon: _retrying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _retrying
                              ? l10n.initialSyncErrorRetrying
                              : l10n.initialSyncErrorRetryButton,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.starGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ],
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
