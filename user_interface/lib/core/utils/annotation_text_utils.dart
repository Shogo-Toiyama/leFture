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

import 'package:lefture/core/utils/sid_citation.dart';
import 'package:lefture/domain/entities/review_card.dart';

class TextLocation {
  const TextLocation({this.blockIdx, required this.startIdx, required this.endIdx});

  final int? blockIdx;
  final int startIdx;
  final int endIdx;
}

/// Parses [markdownSource] the same way flutter_markdown does and
/// concatenates every text leaf in document order (headings, paragraphs,
/// list items, bold/italic runs, ...), with no separators added between
/// blocks -- matching MarkdownAnnotationBuilder's running-offset
/// reconstruction exactly.
String flattenMarkdownText(String markdownSource) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
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
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
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

class SelectionTooBroadException implements Exception {
  final String message;
  const SelectionTooBroadException([this.message = 'The selection is too broad.']);
  
  @override
  String toString() => message;
}

/// 選択された範囲から、元テキスト（引用記号付き）内の対応する引用情報を検索する。
///
/// [rawText] 引用記号 `⟦sXXXXXX⟧` を含んだ元の Markdown テキスト。
/// [startIdx] 表示用プレーンテキスト上での選択開始位置。
/// [endIdx] 表示用プレーンテキスト上での選択終了位置。
///
/// 戻り値:
/// - 該当する `SidCitation`
/// - もし引用がなければ `null`
///
/// 例外:
/// - 選択範囲が引用記号を跨いでいる、または選択範囲の中に引用記号が含まれている場合は `SelectionTooBroadException` をスローする。
SidCitation? findSourceCitation(String rawText, int startIdx, int endIdx) {
  final citations = parseSidCitations(rawText);
  if (citations.isEmpty) return null;

  // インデックス変換マップを作成 (引用記号の除去だけでなく、Markdown構文の
  // フラット化も合わせて考慮したマッピング。startIdx/endIdxはSelectionAreaが
  // 測定する完全フラット化テキスト上の位置なので、これに揃える必要がある)
  final map = buildFlattenedTextMap(rawText);

  // 表示上の位置から元の rawText 上の位置に変換
  final rawStart = map.toRaw(startIdx);
  final rawEnd = map.toRaw(endIdx);

  // 重なり判定と、直後の引用の探索
  SidCitation? closestNextCitation;

  for (final c in citations) {
    // 跨いでいるか、または選択範囲に含まれているか
    // (c.start < rawEnd && c.end > rawStart) のとき重なっている
    if (c.start < rawEnd && c.end > rawStart) {
      throw const SelectionTooBroadException();
    }

    // 選択範囲より後（c.start >= rawEnd）にあるものを検索
    if (c.start >= rawEnd) {
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
///
/// [rawText] 引用記号 `⟦sXXXXXX⟧` を含んだ元の Markdown テキスト。
/// [startIdx] 表示用プレーンテキスト上での選択開始位置。
/// [endIdx] 表示用プレーンテキスト上での選択終了位置。
///
/// 戻り値:
/// - 解決結果の `SourceContextResult`
/// - 引用がなければ `null`
///
/// 例外:
/// - 選択範囲が引用記号を跨いでいる、または選択範囲の中に引用記号が含まれている場合は `SelectionTooBroadException` をスローする。
SourceContextResult? findSourceContextRange(String rawText, int startIdx, int endIdx) {
  final citations = parseSidCitations(rawText);
  if (citations.isEmpty) return null;

  // マッピング関数を作成 (引用記号除去 + Markdown構文フラット化を合わせて考慮)
  final map = buildFlattenedTextMap(rawText);

  // 表示上の位置から元の rawText 上の位置に変換
  final rawStart = map.toRaw(startIdx);
  final rawEnd = map.toRaw(endIdx);

  SidCitation? nextCitation;
  SidCitation? prevCitation;

  for (final c in citations) {
    // 重なり判定
    if (c.start < rawEnd && c.end > rawStart) {
      throw const SelectionTooBroadException();
    }

    // 選択範囲より後（c.start >= rawEnd）
    if (c.start >= rawEnd) {
      if (nextCitation == null || c.start < nextCitation.start) {
        nextCitation = c;
      }
    }

    // 選択範囲より前（c.end <= rawStart）
    if (c.end <= rawStart) {
      if (prevCitation == null || c.end > prevCitation.end) {
        prevCitation = c;
      }
    }
  }

  if (nextCitation == null) {
    return null;
  }

  // 元テキスト上でのハイライトコンテキスト範囲を算出
  final rawContextStart = prevCitation != null ? prevCitation.end : 0;
  final rawContextEnd = nextCitation.start;

  // 表示用テキストのインデックスに戻す
  final contextStartIdx = map.toFlattened(rawContextStart);
  final contextEndIdx = map.toFlattened(rawContextEnd);

  return SourceContextResult(
    citation: nextCitation,
    startIdx: contextStartIdx,
    endIdx: contextEndIdx,
  );
}
