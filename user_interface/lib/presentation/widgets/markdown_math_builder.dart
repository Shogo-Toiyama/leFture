import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// 行内の数式 `$x+1$`。\$ のようにエスケープされた $ は数式の区切りにしない
/// (prepareMathが、数式でない $ を \$ にしてある)。
class MarkdownMathInlineSyntax extends md.InlineSyntax {
  MarkdownMathInlineSyntax() : super(r'(?<!\\)\$([^$\n]+?)(?<!\\)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math_inline', match[1]!));
    return true;
  }
}

/// 別行の数式。prepareMathが `$$` だけの行を前後に置いた形にそろえてあるので、それを読む。
class MarkdownMathBlockSyntax extends md.BlockSyntax {
  const MarkdownMathBlockSyntax();

  static final _fence = RegExp(r'^[ ]{0,3}\$\$[ \t]*$');

  @override
  RegExp get pattern => _fence;

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone && !_fence.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    // 閉じの $$ があれば読み進める(生成中でまだ届いていなければ、そこまでを式として描く)
    if (!parser.isDone) parser.advance();
    // flutter_markdownは知らない名前のブロックを置けないので、段落の中の1要素にする
    return md.Element('p', [
      md.Element.text('math_block', lines.join('\n').trim()),
    ]);
  }
}

/// KaTeX(flutter_math_fork)で数式を描画するMarkdownElementBuilder。
class MarkdownMathElementBuilder extends MarkdownElementBuilder {
  MarkdownMathElementBuilder({
    this.defaultColor,
    required this.block,
    this.fontSize,
  });

  final Color? defaultColor;
  final bool block;
  final double? fontSize;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final fallbackColor = defaultColor ??
        parentStyle?.color ??
        preferredStyle?.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Colors.black87;
    final style = (parentStyle ?? preferredStyle ?? TextStyle(color: fallbackColor))
        .copyWith(fontSize: fontSize ?? parentStyle?.fontSize ?? preferredStyle?.fontSize);

    final plainMath = block ? '\n\\[$tex\\]\n' : '\\($tex\\)';
    final math = Math.tex(
      tex,
      mathStyle: block ? MathStyle.display : MathStyle.text,
      textStyle: style.copyWith(backgroundColor: Colors.transparent),
      // 読めない式はそのまま文字で見せる(生成途中や記述ミス等)
      onErrorFallback: (_) => Text(plainMath, style: style),
    );

    // 数式自体の描画サイズを100%基準にし、余計な空白を完全に排除する。
    // 1. Math.tex 内部の文字たちが SelectionArea に二重登録されてドラッグ選択を阻害しないよう、
    //    SelectionContainer.disabled で包む。
    // 2. 文字を透明(color: Colors.transparent)にしつつ、前後の文章と同じフォントサイズ・行高を
    //    維持したまま ClipRect + OverflowBox で重ねることで、余分な空白を出さずに
    //    選択ハイライト(selectionColor)だけを前後のテキストと同じ自然な太さで背面に描画させる。
    final selectableMath = Stack(
      alignment: block ? Alignment.center : Alignment.centerLeft,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Text(
                plainMath,
                style: style.copyWith(color: Colors.transparent),
              ),
            ),
          ),
        ),
        SelectionContainer.disabled(
          child: IgnorePointer(child: math),
        ),
      ],
    );

    if (block) {
      // SingleChildScrollView(horizontal) を挟むと縦方向のドラッグ選択がScrollable境界で
      // 停止してしまうため、FittedBox(scaleDown)で画面内に収めつつスムーズな縦ドラッグ選択を維持する。
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: selectableMath,
        ),
      );
    }

    // 文章の流れの中に置く(Text.richのWidgetSpanにすると、前後の文字と同じ行に並ぶ)
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: selectableMath,
      ),
    );
  }
}

/// MarkdownBody の builders に渡すヘルパー。
Map<String, MarkdownElementBuilder> markdownMathBuilders({
  Color? defaultColor,
  double? fontSize,
}) =>
    {
      'math_inline': MarkdownMathElementBuilder(
        defaultColor: defaultColor,
        block: false,
        fontSize: fontSize,
      ),
      'math_block': MarkdownMathElementBuilder(
        defaultColor: defaultColor,
        block: true,
        fontSize: fontSize,
      ),
    };
