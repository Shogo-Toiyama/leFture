// lib/domain/entities/annotation.dart
//
// ReviewCard/DeepNoteのmetadata.annotations配列の1要素。
// ハイライト(highlight)やノート(notes)など、ユーザーが本文の一部に付ける
// 注釈を表す。位置はblockIdx(Review Cardsのみ、DeepNotesはnull)+start/end_idx
// で特定し、annotatedWordsは表示コンテンツが変わった際の検証・再アンカリング
// 用のアンカーテキストとして持つ。

class Annotation {
  const Annotation({
    required this.id,
    this.blockIdx,
    required this.startIdx,
    required this.endIdx,
    required this.annotationType,
    required this.annotatedWords,
    required this.contents,
  });

  final String id;
  // Review Cardsのcard_content内のブロックindex。DeepNotesはnull。
  final int? blockIdx;
  final int startIdx;
  final int endIdx;
  // "highlight" | "notes"
  final String annotationType;
  // 保存時点で選択されていたテキスト(検証・再アンカリング用のアンカー)
  final String annotatedWords;
  // highlight: {"type": "marker"|"wave", "color": "..."}
  // notes: ノート本文の文字列
  final dynamic contents;

  factory Annotation.fromMap(Map<String, dynamic> map) {
    return Annotation(
      id: map['id'] as String,
      blockIdx: (map['block_idx'] as num?)?.toInt(),
      startIdx: (map['start_idx'] as num?)?.toInt() ?? 0,
      endIdx: (map['end_idx'] as num?)?.toInt() ?? 0,
      annotationType: map['annotation_type'] as String? ?? 'highlight',
      annotatedWords: map['annotated_words'] as String? ?? '',
      contents: map['contents'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (blockIdx != null) 'block_idx': blockIdx,
      'start_idx': startIdx,
      'end_idx': endIdx,
      'annotation_type': annotationType,
      'annotated_words': annotatedWords,
      'contents': contents,
    };
  }
}
