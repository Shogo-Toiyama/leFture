// lib/presentation/widgets/ai_chat/chat_markdown.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:lefture/core/utils/chat_markdown_text.dart';
import 'package:lefture/core/utils/markdown_bold_syntax.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:markdown/markdown.dart' as md;

/// AIの回答(Markdown)の表示。GFM(表など)・数式・出典の印を描く。
///
/// 本文は先に [prepareMath] → [linkifyCitations] を通す(webappのAssistantMessageと同じ順)。
/// 出典の印 `[3](#cite-3~5)` は押せる小さな印にして、押されたら [onCitationTap] に
/// 出典と押された区切りを渡す。ふつうのリンクは [onOpenLink] に渡す(アプリ内ブラウザで開く)。
/// 選択して「Ask」/返信できるようにするのは、呼び出し側が SelectionArea で包む。
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({
    super.key,
    required this.markdown,
    required this.colors,
    this.citationsByRef = const {},
    this.onCitationTap,
    this.onOpenLink,
    this.fontSize = 15,
  });

  final String markdown;
  final ChatColors colors;

  /// 本文の番号("3" / "W1")→ 出典。ここに無い番号の印は消える。
  final Map<String, ChatCitation> citationsByRef;
  final void Function(ChatCitation citation, List<String> specs)? onCitationTap;
  final void Function(String url)? onOpenLink;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final prepared = linkifyCitations(
      prepareMath(markdown),
      citationsByRef.keys.toSet(),
    );
    return MarkdownBody(
      data: prepared,
      styleSheet: chatMarkdownStyleSheet(colors, fontSize),
      syntaxHighlighter: _PlainCodeSyntaxHighlighter(
        style: TextStyle(
          color: colors.codeText,
          fontSize: fontSize * .86,
          fontFamily: 'Menlo',
          fontFamilyFallback: const ['Roboto Mono', 'Courier'],
          height: 1.5,
        ),
      ),
      checkboxBuilder: (value) => _InteractiveCheckbox(
        initialValue: value,
        colors: colors,
      ),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [...cjkSafeInlineSyntaxes, ChatMathInlineSyntax()],
      blockSyntaxes: const [ChatMathBlockSyntax()],
      builders: {
        'math_inline': _MathBuilder(colors: colors, block: false),
        'math_block': _MathBuilder(colors: colors, block: true),
        'a': _LinkBuilder(
          colors: colors,
          citationsByRef: citationsByRef,
          onCitationTap: onCitationTap,
        ),
      },
      onTapLink: (text, href, title) {
        if (href == null) return;
        if (parseCitationHref(href) != null) return; // 出典の印は _LinkBuilder が受ける
        final uri = Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          onOpenLink?.call(href);
        }
      },
    );
  }
}

/// webappの `.chat-markdown`(index.css)と同じ寸法・色。
MarkdownStyleSheet chatMarkdownStyleSheet(ChatColors c, double fontSize) {
  final base = TextStyle(color: c.text, fontSize: fontSize, height: 1.7);
  final heading = base.copyWith(
    fontWeight: FontWeight.w700,
    color: c.strongText,
    height: 1.5,
  );
  return MarkdownStyleSheet(
    p: base,
    pPadding: EdgeInsets.zero,
    strong: base.copyWith(color: c.strongText, fontWeight: FontWeight.w700),
    em: base.copyWith(fontStyle: FontStyle.italic),
    a: base.copyWith(
      color: c.link,
      decoration: TextDecoration.underline,
      decorationColor: c.link,
    ),
    h1: heading.copyWith(fontSize: fontSize + 1),
    h2: heading.copyWith(fontSize: fontSize + 1),
    h3: heading.copyWith(fontSize: fontSize + 1),
    h4: heading.copyWith(fontSize: fontSize + 1),
    h5: heading,
    h6: heading,
    code: TextStyle(
      color: c.codeText,
      fontSize: fontSize * .86,
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Roboto Mono', 'Courier'],
      backgroundColor: c.codeBackground,
    ),
    codeblockPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    codeblockDecoration: BoxDecoration(
      color: c.preBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.preBorder),
    ),
    blockquote: base.copyWith(color: c.blockquoteText),
    blockquotePadding: const EdgeInsets.only(left: 12),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.blockquoteBorder, width: 2)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: c.rule)),
    ),
    tableBorder: TableBorder.all(color: c.tableBorder),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    tableBody: base.copyWith(fontSize: fontSize * .92),
    tableHead: base.copyWith(
      fontSize: fontSize * .92,
      fontWeight: FontWeight.w700,
    ),
    listBullet: base,
    listIndent: 20,
    blockSpacing: 12,
  );
}

// ---------------------------------------------------------------------------
// 数式($…$ と別行の $$…$$)
// ---------------------------------------------------------------------------

/// 行内の数式 `$x+1$`。\$ のようにエスケープされた $ は数式の区切りにしない
/// (prepareMathが、数式でない $ を \$ にしてある)。
class ChatMathInlineSyntax extends md.InlineSyntax {
  ChatMathInlineSyntax() : super(r'(?<!\\)\$([^$\n]+?)(?<!\\)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math_inline', match[1]!));
    return true;
  }
}

/// 別行の数式。prepareMathが `$$` だけの行を前後に置いた形にそろえてあるので、それを読む。
class ChatMathBlockSyntax extends md.BlockSyntax {
  const ChatMathBlockSyntax();

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

class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.colors, required this.block});

  final ChatColors colors;
  final bool block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final style =
        (parentStyle ?? preferredStyle ?? TextStyle(color: colors.text));
    final math = Math.tex(
      tex,
      mathStyle: block ? MathStyle.display : MathStyle.text,
      textStyle: style.copyWith(backgroundColor: Colors.transparent),
      // 読めない式は、そのまま文字で見せる(生成の途中や、回答役の書き間違いで起きる)
      onErrorFallback: (_) =>
          Text(block ? '\$\$$tex\$\$' : '\$$tex\$', style: style),
    );
    if (block) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: math,
        ),
      );
    }
    // 文章の流れの中に置く(Text.richのWidgetSpanにすると、前後の文字と同じ行に並ぶ)
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: math,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 出典の印
// ---------------------------------------------------------------------------

class _LinkBuilder extends MarkdownElementBuilder {
  _LinkBuilder({
    required this.colors,
    required this.citationsByRef,
    required this.onCitationTap,
  });

  final ChatColors colors;
  final Map<String, ChatCitation> citationsByRef;
  final void Function(ChatCitation citation, List<String> specs)? onCitationTap;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final parsed = parseCitationHref(element.attributes['href']);
    if (parsed == null) return null; // ふつうのリンクは flutter_markdown に任せる
    final citation = citationsByRef[parsed.ref];
    final enabled =
        citation != null &&
        canOpenChatCitation(citation) &&
        onCitationTap != null;
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ChatCiteMarker(
          label: parsed.ref,
          tooltip: citation?.label,
          colors: colors,
          onTap: enabled ? () => onCitationTap!(citation, parsed.specs) : null,
        ),
      ),
    );
  }
}

/// 出典を押したときに、見せられるものがあるか(Webのページ・アプリ内の行き先・抜粋のどれか)。
/// 行き先の有無はアプリ内の画面を引かないと分からないので、ここでは抜粋とURLと区切りだけを見る。
bool canOpenChatCitation(ChatCitation citation) =>
    citation.url != null ||
    (citation.snippet != null && citation.snippet!.isNotEmpty) ||
    citation.passages.isNotEmpty ||
    citation.lectureId != null ||
    citation.courseId != null ||
    citation.threadId != null;

/// 本文中の [n]。webappの `.chat-cite-marker` と同じ形(小さな角丸の印)で、色は控えめ。
class ChatCiteMarker extends StatelessWidget {
  const ChatCiteMarker({
    super.key,
    required this.label,
    required this.colors,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String? tooltip;
  final ChatColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 本文の邪魔をしないよう、出典チップより控えめな色にする(地は薄く、数字も少し透かす)
    final dim = onTap == null ? .6 : 1.0;
    // 幅は中身に合わせる(Containerにalignmentを付けると、WidgetSpanの中で横幅いっぱいに広がる)
    final marker = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.citeBackground.withValues(
            alpha: colors.citeBackground.a * .5 * dim,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: TextStyle(
                  color: colors.citeText.withValues(alpha: .7 * dim),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: tooltip ?? label,
      child: onTap == null
          ? marker
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: marker,
            ),
    );
  }
}

/// コードブロック(pre)のテキスト用ハイライター。
/// インラインcodeと違って背景色を付けず、余計な行ハイライトのないすっきりした等幅ボックスにする。
class _PlainCodeSyntaxHighlighter extends SyntaxHighlighter {
  _PlainCodeSyntaxHighlighter({required this.style});
  final TextStyle style;

  @override
  TextSpan format(String source) => TextSpan(
        style: style.copyWith(backgroundColor: Colors.transparent),
        text: source,
      );
}

/// タップでチェックの切り替えができるチェックボックス。
/// 宇宙(ダーク)・紙(ペーパー)どちらでも見やすい輪郭線とアクセントカラーを持つ。
class _InteractiveCheckbox extends StatefulWidget {
  const _InteractiveCheckbox({
    required this.initialValue,
    required this.colors,
  });

  final bool initialValue;
  final ChatColors colors;

  @override
  State<_InteractiveCheckbox> createState() => _InteractiveCheckboxState();
}

class _InteractiveCheckboxState extends State<_InteractiveCheckbox> {
  late bool _checked = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final isDark = c.sheet.computeLuminance() < 0.5;
    final borderColor = _checked
        ? c.link
        : (isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0x663E3228));
    final bgColor = _checked
        ? c.link
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x143E3228));

    return GestureDetector(
      onTap: () => setState(() => _checked = !_checked),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: 1.6,
            ),
          ),
          child: _checked
              ? Icon(
                  Icons.check,
                  size: 13,
                  color: isDark ? const Color(0xFF121628) : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

