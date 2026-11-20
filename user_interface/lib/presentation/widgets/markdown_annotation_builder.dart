// lib/presentation/widgets/markdown_annotation_builder.dart
//
// Injects Annotation (highlight/notes) decorations into flutter_markdown's
// rendering, by registering a custom MarkdownElementBuilder for every
// text-bearing block tag ('p', 'li', 'h1'-'h6', 'pre') plus the inline tags
// that affect styling ('strong', 'em', 'code'). flutter_markdown only
// routes text nodes to a custom builder registered against the *enclosing
// block* tag, and doesn't expose the inline (bold/italic) style it would
// otherwise apply -- so we track that ourselves via visitElementBefore/
// After on the inline tags and re-merge it manually, to avoid silently
// losing **bold**/_em_ formatting wherever this builder is active.
// Registering every block tag also matters for offset correctness: any
// text in an *unregistered* tag (e.g. a heading, if it weren't listed
// here) would be skipped by this builder entirely and never counted
// toward the running offset below, desyncing it from
// annotation_text_utils.dart's flattenMarkdownText (which walks the same
// document with no tag exclusions). 'pre' (fenced code blocks) is the tag
// this bit most often in practice: flutter_markdown renders its text via a
// special scrollable-code-block path that bypasses custom builders unless
// 'pre' is registered here, but that text is still fully selectable --
// leaving it unregistered meant every highlight/note placed after a code
// block rendered shifted by the code block's length. Registering it means
// fenced code text (always `pre > code`, per the `markdown` package) now
// picks up the 'code' inline style automatically via _inlineStyleStack,
// but we lose flutter_markdown's built-in horizontal-scroll/Scrollbar
// wrapper and codeblockPadding for 'pre', so both are reproduced by hand
// below (_inPreBlock / codeblockPadding).
//
// Offsets in an [Annotation] are measured against flattenMarkdownText's
// output (plain, Markdown-syntax-stripped text), reconstructed here by
// concatenating every visited text leaf in document order.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:lefture/core/utils/annotation_text_utils.dart';
import 'package:lefture/core/utils/term_glossary.dart';
import 'package:lefture/domain/entities/annotation.dart';

/// Tags this builder must be registered under. Callers pass one shared
/// instance to `MarkdownBody(builders: annotationMarkdownBuilders(builder))`.
Map<String, MarkdownElementBuilder> annotationMarkdownBuilders(
  MarkdownAnnotationBuilder builder,
) {
  return {
    for (final tag in const [
      'p',
      'li',
      'strong',
      'em',
      'code',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'pre',
    ])
      tag: builder,
  };
}

/// A stable string derived from [annotations]' content, meant to be used as
/// a `ValueKey` on the enclosing `MarkdownBody`.
///
/// flutter_markdown's `MarkdownWidget` caches its parsed widget tree and
/// only re-parses when `data` or `styleSheet` change (see `didUpdateWidget`
/// in flutter_markdown's widget.dart) -- it has no idea `builders` changed,
/// so adding/erasing a highlight would otherwise silently not repaint until
/// the widget happens to be rebuilt from scratch for some unrelated reason
/// (e.g. navigating away and back). Keying MarkdownBody on this string
/// forces Flutter to treat it as a brand new widget whenever the
/// annotations actually change, which remounts it and reruns the parse.
/// A `bulletBuilder` for `MarkdownBody` that renders list markers
/// (`•`, `1.`, `2.`, ...) exactly as flutter_markdown's own default
/// `_buildBullet` would, but wrapped in `SelectionContainer.disabled`.
///
/// flutter_markdown always inserts the marker as its own widget inside the
/// same SelectionArea as the list item's text, and always counts it as
/// selectable/selected-content length -- but the marker has no
/// corresponding node in the Markdown AST, so flattenMarkdownText (and
/// MarkdownAnnotationBuilder's offset count) never counts it. Left alone,
/// every list item before the selection start pushes the reported
/// `SelectedContentRange` offsets ahead by one marker's worth of
/// characters relative to our own count, and the drift compounds with
/// every prior list item. Excluding the marker from selection makes both
/// sides agree with zero manual compensation, regardless of bullet style,
/// nesting, or how many digits an ordered-list number has.
MarkdownBulletBuilder annotationBulletBuilder(TextStyle? style) {
  return (MarkdownBulletParameters params) {
    final text = params.style == BulletStyle.orderedList
        ? '${params.index + 1}.'
        : '•';
    return SelectionContainer.disabled(
      child: Text(
        text,
        textAlign: params.style == BulletStyle.orderedList
            ? TextAlign.right
            : TextAlign.center,
        style: style,
      ),
    );
  };
}

String annotationsCacheKey(List<Annotation> annotations) {
  final sorted = [...annotations]..sort((a, b) => a.id.compareTo(b.id));
  return sorted
      .map(
        (a) =>
            '${a.id}:${a.startIdx}:${a.endIdx}:${a.annotationType}:${a.contents}',
      )
      .join('|');
}

class MarkdownAnnotationBuilder extends MarkdownElementBuilder {
  MarkdownAnnotationBuilder({
    required List<Annotation> annotations,
    this.onAnnotationTap,
    TermGlossary? terms,
    this.termTopicNumber,
    this.onTermTap,
    TextStyle? codeStyle,
    TextStyle? strongStyle,
    TextStyle? emStyle,
    this.codeblockPadding = EdgeInsets.zero,
  }) : _annotations = [...annotations]
         ..sort((a, b) => a.startIdx.compareTo(b.startIdx)),
       _terms = terms ?? TermGlossary.empty,
       _inlineStyles = {
         'strong': strongStyle ?? const TextStyle(fontWeight: FontWeight.bold),
         'em': emStyle ?? const TextStyle(fontStyle: FontStyle.italic),
         'code': codeStyle ?? const TextStyle(fontFamily: 'monospace'),
       };

  final List<Annotation> _annotations;
  final ValueChanged<Annotation>? onAnnotationTap;

  // 用語マーク(講義キーワード)。見出しごとに「最初の1回だけ」マークし、
  // 見出し・コードの中はマークしない(webappのrehypeTermMarksと同じ規則)。
  // 注釈と重なった箇所は注釈の見た目・タップを優先する。
  final TermGlossary _terms;
  final int? termTopicNumber;
  final ValueChanged<TermEntry>? onTermTap;
  Set<String> _seenTerms = {};
  int _termSkipDepth = 0;
  static const _termSectionTags = {'h1', 'h2', 'h3', 'h4'};
  static const _termSkipTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'code'};
  // 'pre'がbuildersに登録されると、flutter_markdownはコードブロック用の
  // 横スクロール/パディング処理(_ScrollControllerBuilder+codeblockPadding)を
  // 一切適用しなくなる(builder.dartのvisitText参照)。オフセット計算を合わせる
  // ために'pre'を登録する必要がある以上、その見た目はここで手動再現する。
  final EdgeInsetsGeometry codeblockPadding;
  bool _inPreBlock = false;
  int _offset = 0;
  final List<TextStyle> _inlineStyleStack = [];
  // visitText()で生成したTapGestureRecognizerを全て保持しておく。InlineSpanは
  // 自身が持つGestureRecognizerのライフサイクルを管理しないため(Flutter公式ドキュ
  // メント通り)、このビルダーを使い終わったら呼び出し側が[dispose]を呼んで
  // 破棄する必要がある。呼ばないとMarkdownBodyがremountされるたび(highlight/
  // note追加削除、一時ハイライト表示など頻繁に発生する)にRecognizerがリークする。
  final List<TapGestureRecognizer> _recognizers = [];

  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  // flutter_markdownはブロックタグ('p'など)にカスタムbuilderが登録されていると、
  // visitText()に渡すpreferredStyleをブロックのスタイルのみにし、'code'/'strong'/
  // 'em'などインラインタグのstyleSheet設定(色・背景色など)を一切渡さない
  // (builder.dartの`visitText`実装を参照)。そのためcode/strong/emの見た目は
  // このビルダー自身が再現する必要があり、呼び出し側のstyleSheetと食い違わない
  // よう、コンストラクタで実際のstyleSheetのスタイルを渡してもらう。
  final Map<String, TextStyle> _inlineStyles;

  @override
  void visitElementBefore(md.Element element) {
    final style = _inlineStyles[element.tag];
    if (style != null) _inlineStyleStack.add(style);
    if (element.tag == 'pre') _inPreBlock = true;
    if (_termSectionTags.contains(element.tag)) _seenTerms = {};
    if (_termSkipTags.contains(element.tag)) _termSkipDepth++;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (_inlineStyles.containsKey(element.tag) &&
        _inlineStyleStack.isNotEmpty) {
      _inlineStyleStack.removeLast();
    }
    if (element.tag == 'pre') _inPreBlock = false;
    if (_termSkipTags.contains(element.tag) && _termSkipDepth > 0) {
      _termSkipDepth--;
    }
    return null; // let flutter_markdown build the default wrapping widget
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    final content = text.text;
    var effectiveStyle = preferredStyle;
    for (final s in _inlineStyleStack) {
      effectiveStyle = effectiveStyle?.merge(s) ?? s;
    }

    final leafStart = _offset;
    final leafEnd = leafStart + content.length;
    _offset = leafEnd;

    final termMatches = _termSkipDepth > 0
        ? const <TermMatch>[]
        : findTermMatches(content, _terms, _seenTerms, termTopicNumber);

    // 注釈と用語マークの境界すべてで切り、区間ごとに装飾を決める。
    final cuts = <int>{leafStart, leafEnd};
    for (final a in _annotations) {
      if (a.startIdx > leafStart && a.startIdx < leafEnd) cuts.add(a.startIdx);
      if (a.endIdx > leafStart && a.endIdx < leafEnd) cuts.add(a.endIdx);
    }
    for (final m in termMatches) {
      cuts.add(leafStart + m.start);
      cuts.add(leafStart + m.end);
    }
    final boundaries = cuts.toList()..sort();

    final spans = <InlineSpan>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final segStart = boundaries[i];
      final segEnd = boundaries[i + 1];
      if (segEnd <= segStart) continue;
      final segText = content.substring(
        segStart - leafStart,
        segEnd - leafStart,
      );

      // 重なった注釈は開始位置の早いものを優先する(従来と同じ)。
      Annotation? annotation;
      for (final a in _annotations) {
        if (a.startIdx <= segStart && a.endIdx >= segEnd) {
          annotation = a;
          break;
        }
      }

      if (annotation != null) {
        final a = annotation;
        TapGestureRecognizer? recognizer;
        if (onAnnotationTap != null) {
          recognizer = TapGestureRecognizer()
            ..onTap = () => onAnnotationTap?.call(a);
          _recognizers.add(recognizer);
        }
        spans.add(
          TextSpan(
            text: segText,
            style: _decoratedStyle(effectiveStyle, a),
            recognizer: recognizer,
          ),
        );
        // ノートが付いている箇所だと一目でわかるよう、注釈の終端(この区間が
        // アノテーションの最後になる箇所)にゴールドのコメントマークを添える。
        // 複数のleafに跨るアノテーションでも1回だけ表示されるよう、
        // 実際にa.endIdxまで到達したタイミングでのみ追加する。
        if (a.annotationType == 'notes' && segEnd == a.endIdx) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.mode_comment_rounded,
                  size: (effectiveStyle?.fontSize ?? 14) * 0.85,
                  color: const Color(0xFFC5A059),
                ),
              ),
            ),
          );
        }
        continue;
      }

      TermMatch? term;
      for (final m in termMatches) {
        if (leafStart + m.start <= segStart && leafStart + m.end >= segEnd) {
          term = m;
          break;
        }
      }
      if (term != null) {
        final entry = term.entry;
        TapGestureRecognizer? recognizer;
        if (onTermTap != null) {
          recognizer = TapGestureRecognizer()
            ..onTap = () => onTermTap?.call(entry);
          _recognizers.add(recognizer);
        }
        spans.add(
          TextSpan(
            text: segText,
            style: _termStyle(effectiveStyle),
            recognizer: recognizer,
          ),
        );
        continue;
      }

      spans.add(TextSpan(text: segText, style: effectiveStyle));
    }

    final Widget result = spans.isEmpty
        ? Text.rich(TextSpan(text: content, style: effectiveStyle))
        : Text.rich(TextSpan(children: spans));

    if (!_inPreBlock) return result;
    return Padding(
      padding: codeblockPadding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: result,
      ),
    );
  }

  TextStyle _termStyle(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(
      backgroundColor: const Color(0x14FFB300),
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: const Color(0xB3CC8D00),
      decorationThickness: 1.5,
    );
  }

  TextStyle _decoratedStyle(TextStyle? base, Annotation a) {
    final style = base ?? const TextStyle();
    if (a.annotationType == 'notes') {
      return style.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: const Color(0xFFC5A059),
        decorationThickness: 3.0,
      );
    }

    final contents = a.contents;
    final markStyle = contents is Map ? contents['type'] as String? : null;
    final color =
        parseHexColor(contents is Map ? contents['color'] as String? : null) ??
        Colors.yellow;

    switch (markStyle) {
      case 'marker':
        return style.copyWith(backgroundColor: color.withValues(alpha: 0.45));
      case 'line':
        return style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: color,
          decorationThickness: 2,
          decorationStyle: TextDecorationStyle.solid,
        );
      case 'wave':
        return style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: color,
          decorationThickness: 2,
          decorationStyle: TextDecorationStyle.wavy,
        );
      default:
        return style;
    }
  }
}
