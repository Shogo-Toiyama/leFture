import 'package:freezed_annotation/freezed_annotation.dart';

// 生成されるファイル名を指定
part 'lecture_data.freezed.dart';
part 'lecture_data.g.dart';

// -----------------------------------------------------------------------------
// 1. 読む授業 (Markdown) 用のデータモデル
// lecture_complete_data.json に対応
// -----------------------------------------------------------------------------

@freezed
sealed class LectureCompleteData with _$LectureCompleteData {
  const factory LectureCompleteData({
    // "segments" 配列の中身
    required List<LectureSegment> segments,
  }) = _LectureCompleteData;

  factory LectureCompleteData.fromJson(Map<String, dynamic> json) =>
      _$LectureCompleteDataFromJson(json);
}

@freezed
sealed class LectureSegment with _$LectureSegment {
  const factory LectureSegment({
    required int idx,
    required String title,
    
    // JSONのキー名がCamelCaseじゃない場合、@JsonKeyで指定します
    @JsonKey(name: 'start_sid') required String startSid,
    @JsonKey(name: 'end_sid') required String endSid,
    
    // Markdownの本文
    @JsonKey(name: 'detail_content') required String detailContent,
    
    // 豆知識（無い場合も考慮して nullable にしておくと安全です）
    @JsonKey(name: 'fun_fact') String? funFact,
  }) = _LectureSegment;

  factory LectureSegment.fromJson(Map<String, dynamic> json) =>
      _$LectureSegmentFromJson(json);
}

// -----------------------------------------------------------------------------
// 2. トランスクリプト用のデータモデル
// sentences_final.json (リスト形式) の中身1つ分に対応
// -----------------------------------------------------------------------------

@freezed
sealed class TranscriptSentence with _$TranscriptSentence {
  const factory TranscriptSentence({
    required String sid,
    required String text,
    
    // JSONでは "start": 6720 となっているので int (ミリ秒) として扱います
    required int start,
    required int end,
    
    // "lecture", "qa", "chitchat" などの役割
    required String role,
  }) = _TranscriptSentence;

  factory TranscriptSentence.fromJson(Map<String, dynamic> json) =>
      _$TranscriptSentenceFromJson(json);
}