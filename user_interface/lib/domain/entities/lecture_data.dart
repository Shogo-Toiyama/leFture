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
// R2の pipeline_logs/role_classification.json (無ければ transcript_assembled.json)
// のリスト1要素分に対応。
// 形式: {sid, text, start(秒:float), end(秒:float), confidence, role?, role_confidence?}
// -----------------------------------------------------------------------------

class TranscriptSentence {
  final String sid;
  final String text;
  final int start; // ミリ秒
  final int end;   // ミリ秒
  final String role; // "CONTENT", "LOGISTICS" など。role分類前は "CONTENT" 扱い

  const TranscriptSentence({
    required this.sid,
    required this.text,
    required this.start,
    required this.end,
    required this.role,
  });

  /// 講義本編の発話かどうか（それ以外は事務連絡・雑談など）
  bool get isMainContent {
    final r = role.toUpperCase();
    return r == 'CONTENT' || r == 'LECTURE';
  }

  factory TranscriptSentence.fromJson(Map<String, dynamic> json) {
    // バックエンドは秒(float)で保存している。ミリ秒(int)に変換して保持する。
    int toMs(dynamic v) => v is num ? (v * 1000).round() : 0;

    return TranscriptSentence(
      sid: json['sid'] as String? ?? '',
      text: json['text'] as String? ?? '',
      start: toMs(json['start']),
      end: toMs(json['end']),
      role: json['role'] as String? ?? 'CONTENT',
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