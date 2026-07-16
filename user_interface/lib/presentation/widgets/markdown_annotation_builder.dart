// lib/presentation/widgets/markdown_annotation_builder.dart
//
// Injects Annotation (highlight/notes) decorations into flutter_markdown's
// rendering, by registering a custom MarkdownElementBuilder for every
// text-bearing block tag ('p', 'li', 'h1'-'h6') plus the inline tags that
// affect styling ('strong', 'em', 'code'). flutter_markdown only routes
// text nodes to a custom builder registered against the *enclosing block*
// tag, and doesn't expose the inline (bold/italic) style it would
// otherwise apply -- so we track that ourselves via visitElementBefore/
// After on the inline tags and re-merge it manually, to avoid silently
// losing **bold**/_em_ formatting wherever this builder is active.
// Registering every block tag also matters for offset correctness: any
// text in an *unregistered* tag (e.g. a heading, if it weren't listed
// here) would be skipped by this builder entirely and never counted
// toward the running offset below, desyncing it from
// annotation_text_utils.dart's flattenMarkdownText (which walks the same
// document with no tag exclusions).
//
// Offsets in an [Annotation] are measured against flattenMarkdownText's
// output (plain, Markdown-syntax-stripped text), reconstructed here by
// concatenating every visited text leaf in document order.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:lecture_companion_ui/core/utils/annotation_text_utils.dart';
import 'package:lecture_companion_ui/domain/entities/annotation.dart';

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
    TextStyle? codeStyle,
    TextStyle? strongStyle,
    TextStyle? emStyle,
  }) : _annotations = [...annotations]
         ..sort((a, b) => a.startIdx.compareTo(b.startIdx)),
       _inlineStyles = {
         'strong': strongStyle ?? const TextStyle(fontWeight: FontWeight.bold),
         'em': emStyle ?? const TextStyle(fontStyle: FontStyle.italic),
         'code': codeStyle ?? const TextStyle(fontFamily: 'monospace'),
       };

  final List<Annotation> _annotations;
  final ValueChanged<Annotation>? onAnnotationTap;
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

    final spans = <InlineSpan>[];
    var cursor = leafStart;
    for (final a in _annotations) {
      if (a.endIdx <= cursor || a.startIdx >= leafEnd) continue;
      final overlapStart = a.startIdx.clamp(cursor, leafEnd);
      final overlapEnd = a.endIdx.clamp(cursor, leafEnd);
      if (overlapStart > cursor) {
        spans.add(
          TextSpan(
            text: content.substring(
              cursor - leafStart,
              overlapStart - leafStart,
            ),
            style: effectiveStyle,
          ),
        );
      }
      TapGestureRecognizer? recognizer;
      if (onAnnotationTap != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => onAnnotationTap?.call(a);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: content.substring(
            overlapStart - leafStart,
            overlapEnd - leafStart,
          ),
          style: _decoratedStyle(effectiveStyle, a),
          recognizer: recognizer,
        ),
      );
      // ノートが付いている箇所だと一目でわかるよう、注釈の終端(この行が
      // アノテーションの最後のリーフになる箇所)にゴールドのコメントマークを
      // 添える。複数のleafに跨るアノテーションでも1回だけ表示されるよう、
      // 実際にa.endIdxまで到達したタイミングでのみ追加する。
      if (a.annotationType == 'notes' && overlapEnd == a.endIdx) {
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
      cursor = overlapEnd;
    }
    if (cursor < leafEnd) {
      spans.add(
        TextSpan(
          text: content.substring(cursor - leafStart),
          style: effectiveStyle,
        ),
      );
    }

    if (spans.isEmpty) {
      return Text.rich(TextSpan(text: content, style: effectiveStyle));
    }
    return Text.rich(TextSpan(children: spans));
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
