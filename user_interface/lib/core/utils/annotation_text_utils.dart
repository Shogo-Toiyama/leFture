// lib/core/utils/annotation_text_utils.dart
//
// Helpers to convert a raw selected substring (from SelectionArea) into
// (blockIdx, startIdx, endIdx) coordinates against the plain text used to
// store Annotations, and to (de)serialize the small `contents` payload used
// by highlight annotations.
//
// The coordinates MUST be measured against the same "flattened" text that
// MarkdownAnnotationBuilder reconstructs at render time (see
// markdown_annotation_builder.dart) -- i.e. the rendered text with Markdown
// syntax (`#`, `**`, `- `, blank lines between blocks, ...) stripped, NOT
// the raw Markdown source. [flattenMarkdownText] parses the same Markdown
// document flutter_markdown parses and concatenates every text leaf in
// document order, so both sides agree on what "character N" means.

import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:lefture/core/utils/markdown_bold_syntax.dart';
import 'package:lefture/core/utils/sid_citation.dart';
import 'package:lefture/domain/entities/review_card.dart';

class TextLocation {
  const TextLocation({this.blockIdx, required this.startIdx, required this.endIdx});

  final int? blockIdx;
  final int startIdx;
  final int endIdx;
}

/// Matches the `<!-- FIGURE: type="..." title="..." description="..." -->`
/// placeholder comments the topic-details generation prompt inserts. These
/// parse to a bare, tag-less `md.Text` node (see `HtmlBlockSyntax.parse` in
/// the `markdown` package), which flutter_markdown's own builder silently
/// discards (`_blocks.last.tag == null` check in `visitText`) -- it's never
/// rendered and never selectable. [flattenMarkdownText], however, has no tag
/// filter and would otherwise count its raw text, desyncing the flattened
/// coordinate space from what's actually on screen. Stripping the
/// placeholder out of the source before parsing removes the mismatch at the
/// root instead of relying on that undocumented flutter_markdown behavior.
final RegExp _figurePlaceholderPattern = RegExp(
  r'<!--\s*FIGURE:.*?-->\n?',
  dotAll: true,
);

String stripFigurePlaceholders(String markdownSource) =>
    markdownSource.replaceAll(_figurePlaceholderPattern, '');

/// Parses [markdownSource] the same way flutter_markdown does and
/// concatenates every text leaf in document order (headings, paragraphs,
/// list items, bold/italic runs, ...), with no separators added between
/// blocks -- matching MarkdownAnnotationBuilder's running-offset
/// reconstruction exactly.
String flattenMarkdownText(String markdownSource) {
  final document = md.Document(
    inlineSyntaxes: cjkSafeInlineSyntaxes,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(markdownSource));
  final buffer = StringBuffer();

  void visit(md.Node node) {
    if (node is md.Text) {
      buffer.write(node.text);
    } else if (node is md.Element) {
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child);
      }
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  return buffer.toString();
}

/// The exact Markdown source string fed to the block's MarkdownBody --
/// [flattenMarkdownText] this to get the block's canonical plain text.
String reviewCardBlockMarkdownSource(ReviewCardBlock block) {
  switch (block.type) {
    case 'list':
      return (block.items ?? const <String>[])
          .map((item) => '- ${stripSidCitations(item)}')
          .join('\n');
    case 'quote':
    case 'paragraph':
    default:
      return stripSidCitations(block.text ?? '');
  }
}

String reviewCardBlockPlainText(ReviewCardBlock block) =>
    flattenMarkdownText(reviewCardBlockMarkdownSource(block));

/// Same content as [reviewCardBlockMarkdownSource] but WITHOUT stripping SID
/// citations -- this is the "raw" text that source-lookup functions
/// ([findSourceCitation], [findSourceContextRange]) need, since they have to
/// find the citation markers themselves.
String reviewCardBlockRawMarkdownSource(ReviewCardBlock block) {
  switch (block.type) {
    case 'list':
      return (block.items ?? const <String>[]).map((item) => '- $item').join('\n');
    case 'quote':
    case 'paragraph':
    default:
      return block.text ?? '';
  }
}

/// Maps between offsets in [rawMarkdownSource] (SID citations + Markdown
/// syntax intact -- e.g. `card.cardContent[i].text` / `topic.content`) and
/// offsets in its fully-flattened plain text (SID citations AND Markdown
/// syntax both stripped -- i.e. `flattenMarkdownText(stripSidCitations(...))`,
/// the exact text `SelectionArea` measures selections against, and therefore
/// the same coordinate space as `startIdx`/`endIdx` on [TextLocation]).
///
/// [buildStrippedToRawMap]/[buildRawToStrippedMap] in sid_citation.dart only
/// account for citation removal, NOT Markdown syntax removal -- using them
/// directly against a selection's `startIdx`/`endIdx` silently misaligns by
/// however many Markdown syntax characters (`#`, `**`, `- `, ...) precede the
/// selection, which is what made inserted citation markers land in
/// implausible spots. This class composes citation-removal mapping with
/// Markdown-flattening mapping so both steps are accounted for together.
class FlattenedTextMap {
  const FlattenedTextMap(this.flattenedText, this._flattenedToRaw, this._rawToFlattened);

  final String flattenedText;
  final List<int> _flattenedToRaw;
  final List<int> _rawToFlattened;

  int toRaw(int flattenedIdx) =>
      _flattenedToRaw[flattenedIdx.clamp(0, _flattenedToRaw.length - 1)];

  int toFlattened(int rawIdx) =>
      _rawToFlattened[rawIdx.clamp(0, _rawToFlattened.length - 1)];
}

FlattenedTextMap buildFlattenedTextMap(String rawMarkdownSource) {
  final citationStripped = stripSidCitations(rawMarkdownSource);
  final rawToCitationStripped = buildRawToStrippedMap(rawMarkdownSource);
  final citationStrippedToRaw = buildStrippedToRawMap(rawMarkdownSource);

  // Flatten citationStripped the same way flutter_markdown/MarkdownAnnotationBuilder
  // do, while recording -- for every char written to the flattened output --
  // which index in citationStripped it came from.
  final document = md.Document(
    inlineSyntaxes: cjkSafeInlineSyntaxes,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(citationStripped));
  final buffer = StringBuffer();
  final flatToCitationStripped = <int>[];
  var searchCursor = 0;

  void visit(md.Node node) {
    if (node is md.Text) {
      final t = node.text;
      var idx = citationStripped.indexOf(t, searchCursor);
      if (idx < 0) idx = searchCursor.clamp(0, citationStripped.length);
      for (var i = 0; i < t.length; i++) {
        flatToCitationStripped.add(idx + i);
      }
      buffer.write(t);
      searchCursor = idx + t.length;
    } else if (node is md.Element) {
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child);
      }
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  flatToCitationStripped.add(citationStripped.length);

  final flattenedText = buffer.toString();

  final flattenedToRaw = <int>[
    for (final csIdx in flatToCitationStripped)
      citationStrippedToRaw[csIdx.clamp(0, citationStrippedToRaw.length - 1)],
  ];

  // Invert flatToCitationStripped (monotonic non-decreasing) so we can map a
  // citationStripped index to the flattened index of the nearest Markdown
  // text leaf at/after it -- needed for positions that fall inside skipped
  // Markdown syntax (e.g. inside `**`/`- `), which have no direct flattened
  // counterpart.
  final citationStrippedToFlat = List<int>.filled(citationStripped.length + 1, flattenedText.length);
  var fi = 0;
  for (var cs = 0; cs <= citationStripped.length; cs++) {
    while (fi < flatToCitationStripped.length - 1 && flatToCitationStripped[fi] < cs) {
      fi++;
    }
    citationStrippedToFlat[cs] = fi;
  }

  final rawToFlattened = <int>[
    for (var r = 0; r <= rawMarkdownSource.length; r++)
      citationStrippedToFlat[rawToCitationStripped[r].clamp(0, citationStripped.length)],
  ];

  return FlattenedTextMap(flattenedText, flattenedToRaw, rawToFlattened);
}

/// Maps a document-relative selection range (from
/// `SelectableRegionState.getSelection()`) to a specific block + local
/// offset. [range]'s offsets are counted across every Selectable inside the
/// SelectionArea in build order -- for this to line up with block indices,
/// the SelectionArea MUST be scoped to contain ONLY the card's blocks
/// (title/hero emoji excluded via `SelectionContainer.disabled`).
///
/// Returns null if the range is empty/invalid, or spans more than one
/// block (not representable by the current per-block annotation schema).
TextLocation? locateFromReviewCardRange(ReviewCard card, SelectedContentRange range) {
  final start = range.startOffset <= range.endOffset ? range.startOffset : range.endOffset;
  final end = range.startOffset <= range.endOffset ? range.endOffset : range.startOffset;
  if (start >= end) return null;

  var base = 0;
  for (var i = 0; i < card.cardContent.length; i++) {
    final blockEnd = base + reviewCardBlockPlainText(card.cardContent[i]).length;
    if (start >= base && end <= blockEnd) {
      return TextLocation(blockIdx: i, startIdx: start - base, endIdx: end - base);
    }
    base = blockEnd;
  }
  return null;
}

/// Same idea as [locateFromReviewCardRange], but for Deep Notes' single flat
/// body (no block structure -- blockIdx is always null). The SelectionArea
/// must be scoped to contain ONLY the note's MarkdownBody (title/summary/
/// nav arrows excluded), so [range]'s offsets already match the note body's
/// flattened text directly, with no accumulation needed.
TextLocation? locateFromNoteRange(SelectedContentRange range) {
  final start = range.startOffset <= range.endOffset ? range.startOffset : range.endOffset;
  final end = range.startOffset <= range.endOffset ? range.endOffset : range.startOffset;
  if (start >= end) return null;
  return TextLocation(startIdx: start, endIdx: end);
}

String colorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// 広範囲選択時にボトムシートへ渡すためのセクション＆ハイライト情報
class BroadSelectionOption {
  const BroadSelectionOption({
    required this.citation,
    required this.sectionPlainText,
    this.selectedStartInSection,
    this.selectedEndInSection,
  });

  /// 対象の引用情報
  final SidCitation citation;

  /// その引用区間全体の表示用プレーンテキスト
  final String sectionPlainText;

  /// 引用区間内でのユーザー選択範囲の開始インデックス (含まれない場合はnull)
  final int? selectedStartInSection;

  /// 引用区間内でのユーザー選択範囲の終了インデックス (含まれない場合はnull)
  final int? selectedEndInSection;
}

class SelectionTooBroadException implements Exception {
  const SelectionTooBroadException({
    this.message = 'The selection is too broad.',
    this.options = const [],
  });

  final String message;
  final List<BroadSelectionOption> options;

  @override
  String toString() => message;
}

class _TolerantSelectionResult {
  const _TolerantSelectionResult({
    required this.effectiveRawStart,
    required this.effectiveRawEnd,
  });

  final int effectiveRawStart;
  final int effectiveRawEnd;
}

_TolerantSelectionResult _validateAndAdjustSelection({
  required List<SidCitation> citations,
  required FlattenedTextMap map,
  required String rawText,
  required int startIdx,
  required int endIdx,
  required int rawStart,
  required int rawEnd,
}) {
  final selectionLen = (endIdx - startIdx).abs();

  bool isMinor(int len) {
    return len <= 5 || (selectionLen > 0 && (len / selectionLen) <= 0.15);
  }

  // 重なっている引用マーカーをすべて抽出
  final overlapping = <SidCitation>[];
  for (final c in citations) {
    if (c.start < rawEnd && c.end > rawStart) {
      overlapping.add(c);
    }
  }

  List<BroadSelectionOption> buildBroadOptions() {
    final options = <BroadSelectionOption>[];
    for (var i = 0; i < citations.length; i++) {
      final c = citations[i];
      final secRawStart = i == 0 ? 0 : citations[i - 1].end;
      final secRawEnd = c.start;

      if (secRawStart >= secRawEnd) continue;

      // 生Markdown上の選択範囲とセクション範囲の交差を算出
      final rawOverlapStart = rawStart > secRawStart ? rawStart : secRawStart;
      final rawOverlapEnd = rawEnd < secRawEnd ? rawEnd : secRawEnd;

      if (rawOverlapStart < rawOverlapEnd) {
        final secRawChunk = rawText.substring(secRawStart, secRawEnd);
        // セクション単体で完全にフラット化・インデックスマッピングを生成
        final secMap = buildFlattenedTextMap(secRawChunk);

        final secRawStartInSec = rawOverlapStart - secRawStart;
        final secRawEndInSec = rawOverlapEnd - secRawStart;

        final selStartInSec = secMap.toFlattened(secRawStartInSec);
        final selEndInSec = secMap.toFlattened(secRawEndInSec);

        options.add(BroadSelectionOption(
          citation: c,
          sectionPlainText: secMap.flattenedText,
          selectedStartInSection: selStartInSec,
          selectedEndInSection: selEndInSec,
        ));
      }
    }
    return options;
  }

  // 1. 1つの引用マーカーが含まれる場合（単一境界の食い込み）
  if (overlapping.length == 1) {
    final c = overlapping.first;
    final flatBoundary = map.toFlattened(c.start);

    final leftLen = (flatBoundary - startIdx).clamp(0, selectionLen);
    final rightLen = (endIdx - flatBoundary).clamp(0, selectionLen);
    final minorLen = leftLen < rightLen ? leftLen : rightLen;

    if (isMinor(minorLen)) {
      if (leftLen >= rightLen) {
        return _TolerantSelectionResult(
          effectiveRawStart: rawStart,
          effectiveRawEnd: c.start,
        );
      } else {
        return _TolerantSelectionResult(
          effectiveRawStart: c.end,
          effectiveRawEnd: rawEnd,
        );
      }
    }
  }

  // 2. 2つの引用マーカーが含まれる場合（前後両端の食い込み）
  if (overlapping.length == 2) {
    final c1 = overlapping.first;
    final c2 = overlapping.last;

    final flatB1 = map.toFlattened(c1.start);
    final flatB2 = map.toFlattened(c2.start);

    final frontLen = (flatB1 - startIdx).clamp(0, selectionLen);
    final backLen = (endIdx - flatB2).clamp(0, selectionLen);

    if (isMinor(frontLen) && isMinor(backLen)) {
      // 前後ともに5文字以下または15%以下であれば真ん中の区間を採用
      return _TolerantSelectionResult(
        effectiveRawStart: c1.end,
        effectiveRawEnd: c2.start,
      );
    }
  }

  // 許容できない場合または3つ以上のマーカーが含まれる場合
  if (overlapping.isNotEmpty) {
    throw SelectionTooBroadException(
      message: 'The selection spans multiple sections.',
      options: buildBroadOptions(),
    );
  }

  // 重なりがない場合
  return _TolerantSelectionResult(
    effectiveRawStart: rawStart,
    effectiveRawEnd: rawEnd,
  );
}

/// 選択された範囲から、元テキスト（引用記号付き）内の対応する引用情報を検索する。
SidCitation? findSourceCitation(String rawText, int startIdx, int endIdx) {
  final citations = parseSidCitations(rawText);
  if (citations.isEmpty) return null;

  final map = buildFlattenedTextMap(rawText);
  final rawStart = map.toRaw(startIdx);
  final rawEnd = map.toRaw(endIdx);

  final adjusted = _validateAndAdjustSelection(
    citations: citations,
    map: map,
    rawText: rawText,
    startIdx: startIdx,
    endIdx: endIdx,
    rawStart: rawStart,
    rawEnd: rawEnd,
  );

  SidCitation? closestNextCitation;

  for (final c in citations) {
    if (c.start >= adjusted.effectiveRawEnd) {
      if (closestNextCitation == null || c.start < closestNextCitation.start) {
        closestNextCitation = c;
      }
    }
  }

  return closestNextCitation;
}

class SourceContextResult {
  const SourceContextResult({
    required this.citation,
    required this.startIdx,
    required this.endIdx,
  });

  final SidCitation citation;
  final int startIdx;
  final int endIdx;
}

/// 選択された範囲に基づき、対応する引用情報（直後のもの）と一時ハイライトを表示すべきコンテキスト範囲を算出する。
SourceContextResult? findSourceContextRange(String rawText, int startIdx, int endIdx) {
  final citations = parseSidCitations(rawText);
  if (citations.isEmpty) return null;

  final map = buildFlattenedTextMap(rawText);
  final rawStart = map.toRaw(startIdx);
  final rawEnd = map.toRaw(endIdx);

  final adjusted = _validateAndAdjustSelection(
    citations: citations,
    map: map,
    rawText: rawText,
    startIdx: startIdx,
    endIdx: endIdx,
    rawStart: rawStart,
    rawEnd: rawEnd,
  );

  SidCitation? nextCitation;
  SidCitation? prevCitation;

  for (final c in citations) {
    if (c.start >= adjusted.effectiveRawEnd) {
      if (nextCitation == null || c.start < nextCitation.start) {
        nextCitation = c;
      }
    }

    if (c.end <= adjusted.effectiveRawStart) {
      if (prevCitation == null || c.end > prevCitation.end) {
        prevCitation = c;
      }
    }
  }

  if (nextCitation == null) {
    return null;
  }

  final rawContextStart = prevCitation != null ? prevCitation.end : 0;
  final rawContextEnd = nextCitation.start;

  final contextStartIdx = map.toFlattened(rawContextStart);
  final contextEndIdx = map.toFlattened(rawContextEnd);

  return SourceContextResult(
    citation: nextCitation,
    startIdx: contextStartIdx,
    endIdx: contextEndIdx,
  );
}
