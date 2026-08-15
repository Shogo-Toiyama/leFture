import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/app_config/app_config_provider.dart';
import 'package:lefture/application/connectivity/connectivity_status_provider.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// アプリ全体共通で、画面上部（ステータスバー下）にスムーズなSpotifyスタイルの
/// トップバナーを表示する。コンテンツ全体を下に押し下げるため、レイアウト崩れが
/// 発生しない。
///
/// 2種類の状態を扱う(同時には出さず、オフラインを優先する):
/// - オフライン中(青): 端末が実際にネットワークに繋がっていない
/// - メンテナンス中(黄): 端末はオンラインだが、[AppGateOverlay]の
///   「このまま使う」を押してメンテナンス中も閲覧を続けている状態。
///   青バナーと違い「オフラインです」という嘘をつかず、正直に
///   「一部機能が使えない理由」を伝え続ける。
class StatusBanner extends ConsumerWidget {
  const StatusBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 接続状態が判明するまで(初回のみ)はバナーを出さない(trueをデフォルトに)。
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;
    final appConfig = ref.watch(appConfigControllerProvider);
    final showMaintenanceBanner =
        isOnline && appConfig.maintenance && appConfig.acknowledged;
    final showAnyBanner = !isOnline || showMaintenanceBanner;
    final topPadding = MediaQuery.of(context).padding.top;

    Widget bannerContent;
    if (!isOnline) {
      bannerContent = _BannerContent(
        key: const ValueKey('offline'),
        color: AppColors.cosmicBlue,
        icon: Icons.wifi_off_rounded,
        message: l10n.offlineBannerMessage,
        topPadding: topPadding,
      );
    } else if (showMaintenanceBanner) {
      bannerContent = _BannerContent(
        key: const ValueKey('maintenance'),
        color: AppColors.starGold,
        textColor: Colors.black,
        icon: Icons.build_circle_outlined,
        message: l10n.maintenanceBannerMessage,
        topPadding: topPadding,
      );
    } else {
      bannerContent = const SizedBox(width: double.infinity, height: 0);
    }

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          child: bannerContent,
        ),
        Expanded(
          child: showAnyBanner
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                )
              : child,
        ),
      ],
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    super.key,
    required this.color,
    required this.icon,
    required this.message,
    required this.topPadding,
    this.textColor = Colors.white,
  });

  final Color color;
  final Color textColor;
  final IconData icon;
  final String message;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: textColor,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      letterSpacing: 0.2,
      decoration: TextDecoration.none,
    );

    return Material(
      color: color,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          top: topPadding > 0 ? topPadding + 2 : 6,
          bottom: 6,
          left: 14,
          right: 14,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: _MarqueeText(
                text: message,
                style: textStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画面幅に収まらない場合に右から左へスムーズに文字が流れるティッカーウィジェット
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  late final ScrollController _scrollController;
  Timer? _timer;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  void _updateScrollTimer(bool shouldScroll) {
    if (shouldScroll == _needsScroll) return;
    _needsScroll = shouldScroll;
    if (shouldScroll) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll <= 0) return;

        final current = _scrollController.offset;
        final next = current + 1.0;
        if (next >= maxScroll) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.jumpTo(next);
        }
      });
    } else {
      _timer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();

        final isOverflowing = textPainter.width > constraints.maxWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateScrollTimer(isOverflowing);
        });

        // 画面幅に収まる短い文字列（例：「オフラインです」）は中央に1つだけ静止表示
        if (!isOverflowing) {
          return Center(
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
            ),
          );
        }

        // 画面幅を超える長い文字列は右から左へスムーズに流す
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                style: widget.style,
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: 48),
              Text(
                widget.text,
                style: widget.style,
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ),
        );
      },
    );
  }
}
