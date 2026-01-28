// lib/domain/entities/lecture_data.dart

// -----------------------------------------------------------------------------
// 1. 読む授業 (Markdown) 用のデータモデル
// lecture_complete_data.json に対応
// -----------------------------------------------------------------------------

class LectureCompleteData {
  final List<LectureSegment> segments;

  const LectureCompleteData({
    required this.segments,
  });

  factory LectureCompleteData.fromJson(Map<String, dynamic> json) {
    return LectureCompleteData(
      segments: (json['segments'] as List<dynamic>)
          .map((e) => LectureSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'segments': segments.map((e) => e.toJson()).toList(),
    };
  }
}

class LectureSegment {
  final int idx;
  final String title;
  final String startSid;      // start_sid
  final String endSid;        // end_sid
  final String detailContent; // detail_content
  final String? funFact;      // fun_fact (nullable)

  const LectureSegment({
    required this.idx,
    required this.title,
    required this.startSid,
    required this.endSid,
    required this.detailContent,
    this.funFact,
  });

  factory LectureSegment.fromJson(Map<String, dynamic> json) {
    return LectureSegment(
      idx: json['idx'] as int,
      title: json['title'] as String,
      startSid: json['start_sid'] as String,
      endSid: json['end_sid'] as String,
      detailContent: json['detail_content'] as String,
      funFact: json['fun_fact'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idx': idx,
      'title': title,
      'start_sid': startSid,
      'end_sid': endSid,
      'detail_content': detailContent,
      'fun_fact': funFact,
    };
  }
}

// -----------------------------------------------------------------------------
// 2. トランスクリプト用のデータモデル
// sentences_final.json (リスト形式) の中身1つ分に対応
// -----------------------------------------------------------------------------

class TranscriptSentence {
  final String sid;
  final String text;
  final int start; // ミリ秒
  final int end;   // ミリ秒
  final String role; // "lecture", "qa", "chitchat" など

  const TranscriptSentence({
    required this.sid,
    required this.text,
    required this.start,
    required this.end,
    required this.role,
  });

  factory TranscriptSentence.fromJson(Map<String, dynamic> json) {
    return TranscriptSentence(
      sid: json['sid'] as String,
      text: json['text'] as String,
      start: json['start'] as int,
      end: json['end'] as int,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sid': sid,
      'text': text,
      'start': start,
      'end': end,
      'role': role,
    };
  }
}