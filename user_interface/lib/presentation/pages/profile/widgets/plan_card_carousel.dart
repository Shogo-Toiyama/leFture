import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'plan_card.dart';
import 'plan_purchase_state.dart';

/// プランカードの「スタック」UI。中央(front)のカードの奥に、残りの
/// カードが右→左の優先順(右2枚・左1枚が基本)で少しずれて覗く。片側に
/// カードが無い(先頭/末尾のプランがfrontの時)は、もう片方に最大3枚まで
/// 積み重なって見える。右にスワイプすると前のカードへ(今のカードは
/// そのまま後ろ・右側に重なって下がる)、左にスワイプすると次のカードへ
/// (次のカードが下から上がってfrontになる)。PlanTabBarとは
/// selectedIndex を介して双方向に同期する。
class PlanCardCarousel extends StatefulWidget {
  const PlanCardCarousel({
    super.key,
    required this.plans,
    required this.selectedIndex,
    required this.onPageChanged,
    required this.summary,
    required this.offerings,
    required this.purchasingPlanId,
    required this.pendingPlanId,
  });

  final List<PlanOption> plans;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final CreditSummary? summary;
  final Offerings? offerings;
  final String? purchasingPlanId;

  /// summary.pendingPlanIdをそのまま受け渡す(予約先プランのカードに
  /// 「NEXT PLAN」チップを出すため)。
  final String? pendingPlanId;

  @override
  State<PlanCardCarousel> createState() => _PlanCardCarouselState();
}

class _PlanCardCarouselState extends State<PlanCardCarousel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _anchorIndex;
  double _startOffset = 0.0;
  double _endOffset = 0.0;
  bool _isDragging = false;
  double _dragDx = 0.0;
  double _cardWidth = 300.0;

  @override
  void initState() {
    super.initState();
    _anchorIndex = widget.selectedIndex;
    _controller = AnimationController(duration: const Duration(milliseconds: 320), vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlanCardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _anchorIndex && !_isDragging) {
      final startNow = _controller.isAnimating ? _currentOffset : 0.0;
      _controller.stop();
      _animateOffset(startNow, (widget.selectedIndex - _anchorIndex).toDouble(), onDone: () {
        _anchorIndex = widget.selectedIndex;
      });
    }
  }

  void _animateOffset(double from, double to, {required VoidCallback onDone}) {
    _startOffset = from;
    _endOffset = to;
    _controller.value = 0;
    _controller.forward().whenComplete(() {
      onDone();
      setState(() {
        _controller.value = 0;
        _startOffset = 0;
        _endOffset = 0;
      });
    });
  }

  double get _currentOffset {
    if (_isDragging) {
      final raw = -_dragDx / _cardWidth;
      final atStart = _anchorIndex == 0;
      final atEnd = _anchorIndex == widget.plans.length - 1;
      final lower = atStart ? -0.15 : -1.0;
      final upper = atEnd ? 0.15 : 1.0;
      return raw.clamp(lower, upper);
    }
    if (_controller.isAnimating) {
      final t = Curves.easeOutCubic.transform(_controller.value);
      return _startOffset + (_endOffset - _startOffset) * t;
    }
    return 0.0;
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    setState(() {
      _isDragging = true;
      _dragDx = 0.0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDx += details.delta.dx;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final rawOffset = -_dragDx / _cardWidth;
    final velocity = details.primaryVelocity ?? 0.0;
    final atStart = _anchorIndex == 0;
    final atEnd = _anchorIndex == widget.plans.length - 1;

    var dir = 0;
    final committed = rawOffset.abs() > 0.35 || velocity.abs() > 700;
    if (committed) {
      dir = rawOffset >= 0 ? 1 : -1;
      if (dir == 1 && atEnd) dir = 0;
      if (dir == -1 && atStart) dir = 0;
    }
    final startOffsetVal = rawOffset.clamp(atStart ? -0.15 : -1.0, atEnd ? 0.15 : 1.0);

    setState(() {
      _isDragging = false;
    });

    if (dir == 0) {
      _animateOffset(startOffsetVal, 0.0, onDone: () {});
    } else {
      final nextIndex = _anchorIndex + dir;
      final from = startOffsetVal - dir;
      _anchorIndex = nextIndex;
      widget.onPageChanged(nextIndex);
      _animateOffset(from, 0.0, onDone: () {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offset = _currentOffset;
    final position = _anchorIndex + offset;

    final items = <_StackItem>[];
    for (var i = 0; i < widget.plans.length; i++) {
      final rel = i - position;
      if (rel.abs() >= 4) continue;
      items.add(_StackItem(index: i, rel: rel));
    }
    // 前面(rel絶対値が小さいカード)を後で描画してz順を最前面にする。
    items.sort((a, b) => b.rel.abs().compareTo(a.rel.abs()));

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _cardWidth = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final item in items) _buildCard(context, l10n, item, constraints),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.plans.length, (index) {
            final isSelected = index == widget.selectedIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isSelected ? 20.0 : 6.0,
              height: 6.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: isSelected ? AppColors.starGold : AppColors.universe.textComet.withValues(alpha: 0.4),
                boxShadow: isSelected
                    ? [BoxShadow(color: AppColors.starGold.withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 1)]
                    : [],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AppLocalizations l10n, _StackItem item, BoxConstraints constraints) {
    final plan = widget.plans[item.index];
    final slot = _slotForRel(item.rel);
    final purchaseState = resolvePlanPurchaseState(
      l10n: l10n,
      plan: plan,
      summary: widget.summary,
      offerings: widget.offerings,
    );

    return IgnorePointer(
      ignoring: item.rel.abs() > 0.4,
      child: Opacity(
        opacity: slot.opacity,
        child: Transform.translate(
          offset: slot.translate,
          child: Transform.rotate(
            angle: slot.rotation,
            child: Transform.scale(
              scale: slot.scale,
              child: SizedBox(
                width: constraints.maxWidth * 0.74,
                height: constraints.maxHeight * 0.94,
                child: PlanCard(
                  plan: plan,
                  state: purchaseState,
                  isPurchasing: widget.purchasingPlanId == plan.id,
                  isPendingTarget: widget.pendingPlanId == plan.id,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StackItem {
  const _StackItem({required this.index, required this.rel});
  final int index;
  final double rel;
}

class _CardSlot {
  const _CardSlot(this.translate, this.scale, this.rotation, this.opacity);
  final Offset translate;
  final double scale;
  final double rotation;
  final double opacity;
}

const _frontSlot = _CardSlot(Offset.zero, 1.0, 0.0, 1.0);

_CardSlot _lerpSlot(_CardSlot a, _CardSlot b, double t) {
  return _CardSlot(
    Offset.lerp(a.translate, b.translate, t) ?? a.translate,
    lerpDouble(a.scale, b.scale, t) ?? a.scale,
    lerpDouble(a.rotation, b.rotation, t) ?? a.rotation,
    lerpDouble(a.opacity, b.opacity, t) ?? a.opacity,
  );
}

/// 前面から数えてdepth枚目(1,2,3,...)、side(+1=右側, -1=左側)の見た目。
/// depthが深いほど、ずれ・縮小・回転・不透明度の減衰が大きくなる。
_CardSlot _slotAtDepth(int depth, int side) {
  final d = depth.toDouble();
  return _CardSlot(
    Offset(24.0 * d * side, 18.0 * d),
    (1.0 - 0.06 * d).clamp(0.4, 1.0),
    0.045 * d * side,
    (1.0 - 0.15 * (d - 1)).clamp(0.0, 1.0),
  );
}

/// rel = カードのインデックス - 現在の連続位置。0=前面、正=右側、負=左側。
/// 深さはrelの絶対値だけで決まるので、片側にカードが無い(先頭/末尾の
/// プランが前面の時)は、自動的にもう片方に最大3枚まで積み重なって見える
/// (左右で別々の配分ロジックを持つ必要が無い)。
_CardSlot _slotForRel(double rel) {
  if (rel == 0) return _frontSlot;
  final side = rel > 0 ? 1 : -1;
  final absRel = rel.abs();
  final lowerDepth = absRel.floor();
  final upperDepth = lowerDepth + 1;
  final t = absRel - lowerDepth;
  final lowerSlot = lowerDepth == 0 ? _frontSlot : _slotAtDepth(lowerDepth, side);
  final upperSlot = _slotAtDepth(upperDepth, side);
  final slot = _lerpSlot(lowerSlot, upperSlot, t);
  if (absRel > 3.5) {
    return _CardSlot(slot.translate, slot.scale, slot.rotation, 0.0);
  }
  return slot;
}
