// lib/presentation/widgets/selection_swipe_priority.dart
//
// SelectionArea(SelectableRegion)は、タッチ端末では横ドラッグをそのまま
// 「ドラッグして選択」に使うTapAndHorizontalDragGestureRecognizerを内部に持つ。
// しかもiOS以外ではeagerVictoryOnDragがtrueなので、テキストの上で横に指を
// 動かした瞬間にジェスチャーアリーナを即座に勝ち取ってしまう(Flutter SDKの
// selectable_region.dart _initTouchGestureRecognizer参照)。そのため
// SelectionAreaを祖先の横スワイプ(カードめくりやPageView)と同居させると、
// テキストの上から始めたスワイプが一切効かなくなる。
//
// 同じ閾値の横ドラッグ認識器同士では「ツリーで深い方が先にポインタを受け取り、
// 先に勝つ」(SDK側も同じ理屈をselectable_region.dartのコメントで説明している)。
// したがってSelectionAreaの *内側* に横ドラッグ認識器を置けば、プラット
// フォームに関係なくスワイプ側を勝たせられる。指が止まっている長押しは
// こちらが勝ちを主張しないため、長押し起点のテキスト選択はそのまま生き残る。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/selection_floating_menu.dart';

/// 選択がある間だけポインタを辞退する横ドラッグ認識器。
///
/// 選択済みのテキストの上で指が少しずれただけで選択が解除されるのを避けるため、
/// その場合に限ってドラッグをSelectionAreaに譲る。
class SelectionAwareHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  SelectionAwareHorizontalDragRecognizer({
    super.debugOwner,
    required this.shouldDefer,
  });

  final ValueGetter<bool> shouldDefer;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (shouldDefer()) return false;
    return super.isPointerAllowed(event);
  }
}

/// 祖先の横スクロール(PageViewなど)を殺さずに中身を選択可能にする
/// [SelectionArea]。
///
/// 横ドラッグは最も近い横方向の[Scrollable]へ転送するので、ページスナップや
/// フリングの物理は純正のまま保たれる。選択は長押し起点のみになり、選んだ文章の近くに
/// 浮かぶメニュー(「AIに聞く」「コピー」。Deep Notes・復習カードと同じ形)が出る。
class SwipePrioritySelectionArea extends StatefulWidget {
  const SwipePrioritySelectionArea({
    super.key,
    required this.child,
    this.askLabel,
    this.onAsk,
    this.copyLabel,
    this.world = ChatWorld.universe,
  });

  final Widget child;

  /// 選択のメニューに足す「AIに聞く」(AIチャットに、選んだ文章を添えて聞く)。[onAsk]と一緒に渡す。
  final String? askLabel;
  final void Function(String selectedText)? onAsk;

  /// 「コピー」の文言。渡さなければ端末標準の文言。
  final String? copyLabel;

  /// メニューの色(宇宙の画面は暗く、紙の画面は紙の色)。
  final ChatWorld world;

  @override
  State<SwipePrioritySelectionArea> createState() =>
      _SwipePrioritySelectionAreaState();
}

class _SwipePrioritySelectionAreaState
    extends State<SwipePrioritySelectionArea> {
  bool _hasSelection = false;
  String _selectedText = '';
  Drag? _drag;

  void _handleDragStart(DragStartDetails details) {
    // Flutter自身もドラッグ処理中に同じ探索をしている(text_selection.dartの
    // _scrollPosition)ので、build外でScrollableを引くのは想定内の使い方。
    // axisを指定して、間にある縦スクロールを飛ばして横のPageViewだけを掴む。
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    _drag = position?.drag(details, _disposeDrag);
  }

  void _handleDragUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _handleDragEnd(DragEndDetails details) => _drag?.end(details);

  void _handleDragCancel() => _drag?.cancel();

  void _disposeDrag() => _drag = null;

  @override
  Widget build(BuildContext context) {
    final onAsk = widget.onAsk;
    final askLabel = widget.askLabel;
    return SelectionArea(
      onSelectionChanged: (content) {
        final hasSelection = content != null && content.plainText.isNotEmpty;
        _selectedText = content?.plainText ?? '';
        if (hasSelection != _hasSelection) {
          setState(() => _hasSelection = hasSelection);
        }
      },
      contextMenuBuilder: (context, state) {
        final text = _selectedText.trim();
        return buildSelectionFloatingMenu(
          state: state,
          world: widget.world,
          actions: [
            if (onAsk != null && askLabel != null && text.isNotEmpty)
              SelectionMenuAction(
                label: askLabel,
                emphasized: true,
                onTap: () {
                  state.clearSelection();
                  onAsk(text);
                },
              ),
            SelectionMenuAction(
              label:
                  widget.copyLabel ??
                  MaterialLocalizations.of(context).copyButtonLabel,
              onTap: () {
                unawaited(Clipboard.setData(ClipboardData(text: text)));
                state.clearSelection();
              },
            ),
          ],
        );
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          SelectionAwareHorizontalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                SelectionAwareHorizontalDragRecognizer
              >(
                () => SelectionAwareHorizontalDragRecognizer(
                  debugOwner: this,
                  shouldDefer: () => _hasSelection,
                ),
                (recognizer) {
                  recognizer
                    ..onStart = _handleDragStart
                    ..onUpdate = _handleDragUpdate
                    ..onEnd = _handleDragEnd
                    ..onCancel = _handleDragCancel;
                },
              ),
        },
        child: widget.child,
      ),
    );
  }
}
