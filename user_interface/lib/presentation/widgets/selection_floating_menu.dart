// lib/presentation/widgets/selection_floating_menu.dart
import 'package:flutter/material.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// 選んだ文章の近くに浮かぶメニューの1項目(webappの `.annotation-toolbar-row button`)。
class SelectionMenuAction {
  const SelectionMenuAction({
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.active = false,
    this.swatch,
  });

  final String label;
  final VoidCallback onTap;

  /// 「AIに聞く」のように目立たせる項目(webappの `.annotation-ask-btn`: 金の太字)。
  final bool emphasized;

  /// ハイライトの色の見本の丸を、ラベルの前に出す。
  final Color? swatch;

  /// 開いている最中(ハイライトのサブツールバーなど)の見た目。
  final bool active;
}

/// 文章を選ぶと選択範囲のそばに浮かぶメニュー。Deep Notes・復習カード・Fun Fact で同じ形を使う
/// (webappの AnnotationLayer / SelectionAskArea と同じ: 角丸の小さな板に、文字だけのボタンが並ぶ)。
///
/// [SelectionArea.contextMenuBuilder] から呼ぶ。位置と、ハンドルを動かしている間の出し入れは
/// Flutterの選択のしくみに任せる。項目を押すとメニューは閉じる(選択は残るので、ハイライトなど
/// 選択のまま続く操作が使える。選択を消したい項目は、押された側で消す)。
Widget buildSelectionFloatingMenu({
  required SelectableRegionState state,
  required ChatWorld world,
  required List<SelectionMenuAction> actions,
}) {
  return SelectionFloatingMenu(
    anchors: state.contextMenuAnchors,
    world: world,
    actions: [
      for (final a in actions)
        SelectionMenuAction(
          label: a.label,
          emphasized: a.emphasized,
          active: a.active,
          swatch: a.swatch,
          onTap: () {
            state.hideToolbar(false);
            a.onTap();
          },
        ),
    ],
  );
}

class SelectionFloatingMenu extends StatelessWidget {
  const SelectionFloatingMenu({
    super.key,
    required this.anchors,
    required this.world,
    required this.actions,
  });

  final TextSelectionToolbarAnchors anchors;
  final ChatWorld world;
  final List<SelectionMenuAction> actions;

  static const _height = 40.0;
  static const _gap = 10.0;
  static const _screenPadding = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(world);
    final paddingTop = MediaQuery.paddingOf(context).top + _screenPadding;
    final fitsAbove =
        anchors.primaryAnchor.dy - _gap - _height >= paddingTop;
    final local = Offset(_screenPadding, paddingTop);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _screenPadding,
        paddingTop,
        _screenPadding,
        _screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - local - const Offset(0, _gap),
          anchorBelow:
              (anchors.secondaryAnchor ?? anchors.primaryAnchor) -
              local +
              const Offset(0, _gap),
          fitsAbove: fitsAbove,
        ),
        child: Material(
          color: c.menuBackground,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: .35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.menuBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: _height,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in actions) _MenuButton(action: a, colors: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.action, required this.colors});

  final SelectionMenuAction action;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final color = action.emphasized || action.active
        ? c.accent
        : c.actionForegroundStrong;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: action.onTap,
      child: Container(
        height: SelectionFloatingMenu._height - 8,
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: action.active ? c.actionHover : null,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.swatch != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: action.swatch,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: c.menuBorder),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              action.label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: action.emphasized
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
