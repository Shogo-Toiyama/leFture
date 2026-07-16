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

import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';

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
