// lib/presentation/widgets/ai_chat/chat_thinking_indicator.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/ai_chat/thinking_nebula.dart';

/// 経過秒数を出し始める秒数(2026-10-18に決定。それまでは星雲と文言だけ)。
const chatElapsedVisibleAfterSeconds = 5;

/// 返答を待っているあいだの表示: 星雲(形と色が2秒ごとにランダムに変わる) + 段階の文言 + 経過秒数。
///
/// [startedAt]は、この返答を待ち始めた時刻(送った時刻)。画面を開き直しても、続きの秒数が出る。
class ChatThinkingIndicator extends StatefulWidget {
  const ChatThinkingIndicator({
    super.key,
    required this.label,
    required this.world,
    required this.colors,
    required this.startedAt,
    this.nebulaSize = 34,
  });

  final String label;
  final ChatWorld world;
  final ChatColors colors;
  final DateTime startedAt;
  final double nebulaSize;

  @override
  State<ChatThinkingIndicator> createState() => _ChatThinkingIndicatorState();
}

class _ChatThinkingIndicatorState extends State<ChatThinkingIndicator> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _seconds = _elapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _elapsed();
      if (next != _seconds) setState(() => _seconds = next);
    });
  }

  /// 端末の時計とサーバーの時刻が少しずれていても、マイナスにはしない。
  int _elapsed() => DateTime.now()
      .toUtc()
      .difference(widget.startedAt.toUtc())
      .inSeconds
      .clamp(0, 86400);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final showSeconds = _seconds >= chatElapsedVisibleAfterSeconds;
    final labelStyle = TextStyle(
      fontSize: 13.5,
      height: 1.5,
      color: widget.colors.stageText,
    );
    return Semantics(
      liveRegion: true,
      label: widget.label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ThinkingNebula(world: widget.world, size: widget.nebulaSize),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: reduceMotion
                        ? Text(widget.label, style: labelStyle)
                        : _ShimmerText(
                            text: widget.label,
                            style: labelStyle,
                            colors: widget.colors,
                          ),
                  ),
                  if (showSeconds)
                    TextSpan(
                      text: '  ${chatElapsedLabel(l10n, _seconds)}',
                      style: labelStyle.copyWith(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文言の上を、明るい帯がゆっくり流れる(webappの `.slabel` と同じ)。
class _ShimmerText extends StatefulWidget {
  const _ShimmerText({
    required this.text,
    required this.style,
    required this.colors,
  });

  final String text;
  final TextStyle style;
  final ChatColors colors;

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.colors.stageText;
    final bright = widget.colors.actionForegroundStrong;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 帯が左から右へ流れる。0→1で、帯の中心が -0.4 → 1.4 に動く
        final center = -.4 + _controller.value * 1.8;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [base, bright, base],
            stops: [
              (center - .25).clamp(0.0, 1.0),
              center.clamp(0.0, 1.0),
              (center + .25).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: Text(
        widget.text,
        style: widget.style.copyWith(color: Colors.white),
      ),
    );
  }
}
