// lib/core/utils/chat_citation_target.dart
import 'package:lefture/domain/entities/chat.dart';

/// 出典を押したときの行き先。webappの chatCitations.ts の citationRoute / citationUrl のアプリ版。
///
/// アプリのルートはコースIDも要る(`/home/courses/c/:courseId/...`)ので、行き先は「どの種類のページか」までを
/// 持ち、道順(パス)は[chatCitationPath]がコースIDを受けて作る。コースIDは出典に入っていればそれを使い、
/// 無ければ呼び出し側が講義IDから端末のDBで引く。
sealed class ChatCitationTarget {
  const ChatCitationTarget();
}

/// Webのページ(アプリ内ブラウザで開く)。
class CitationWebTarget extends ChatCitationTarget {
  const CitationWebTarget(this.url);
  final String url;
}

/// 過去の会話(今のシートの中で、そのスレッドを開く)。
class CitationThreadTarget extends ChatCitationTarget {
  const CitationThreadTarget(this.threadId);
  final String threadId;
}

/// コースのページ。
class CitationCourseTarget extends ChatCitationTarget {
  const CitationCourseTarget(this.courseId);
  final String courseId;
}

enum ChatLecturePage { lecture, deepNotes, reviewCards, transcript }

/// 講義の中のページ。[courseId]が出典に入っていれば持つ。
class CitationLectureTarget extends ChatCitationTarget {
  const CitationLectureTarget({
    required this.page,
    required this.lectureId,
    this.courseId,
    this.startSid,
    this.endSid,
  });

  final ChatLecturePage page;
  final String lectureId;
  final String? courseId;

  /// トランスクリプトの、引用された文の範囲(sentence_rangeの両端)
  final String? startSid;
  final String? endSid;
}

/// Webのページの出典なら、そのURL(http/httpsのものだけ)。
String? chatCitationUrl(ChatCitation citation) {
  if (citation.sourceType != 'web' || citation.url == null) return null;
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(citation.url!)
      ? citation.url
      : null;
}

/// 出典を押したときの行き先。講義に紐づかない出典(講義の無いお知らせ等)はnull。
/// 添付資料は引用箇所のプレビューだけ(資料の一覧から全文を読める)。
ChatCitationTarget? chatCitationTarget(ChatCitation c) {
  final url = chatCitationUrl(c);
  if (url != null) return CitationWebTarget(url);
  switch (c.sourceType) {
    case 'web':
    case 'chat_attachment':
      return null;
    case 'course':
      return c.courseId == null ? null : CitationCourseTarget(c.courseId!);
    case 'chat_turn':
      return c.threadId == null ? null : CitationThreadTarget(c.threadId!);
  }
  final lectureId = c.lectureId;
  if (lectureId == null) return null;
  CitationLectureTarget page(
    ChatLecturePage p, {
    String? startSid,
    String? endSid,
  }) => CitationLectureTarget(
    page: p,
    lectureId: lectureId,
    courseId: c.courseId,
    startSid: startSid,
    endSid: endSid,
  );
  switch (c.sourceType) {
    case 'deep_note':
      // Deep Notesのトピックの詳細は、一覧から開く作り(トピックの一覧を画面に渡す)なので、まず一覧へ
      return page(ChatLecturePage.deepNotes);
    case 'review_card':
      return page(ChatLecturePage.reviewCards);
    case 'transcript_topic':
      final range = c.metadata['sentence_range'];
      if (range is String && range.trim().isNotEmpty) {
        final parts = range.split('-').map((s) => s.trim()).toList();
        return page(
          ChatLecturePage.transcript,
          startSid: parts.first.isEmpty ? null : parts.first,
          endSid: parts.length > 1 && parts.last.isNotEmpty ? parts.last : null,
        );
      }
      return page(ChatLecturePage.transcript);
    default:
      return page(ChatLecturePage.lecture);
  }
}

/// アプリ内の道順(GoRouterのパス)。コースIDが分からなければnull。
String? chatCitationPath(CitationLectureTarget t, String? courseId) {
  final course = t.courseId ?? courseId;
  if (course == null) return null;
  final base = '/home/courses/c/$course';
  switch (t.page) {
    case ChatLecturePage.lecture:
      return '$base/v/${t.lectureId}';
    case ChatLecturePage.deepNotes:
      return '$base/dn/${t.lectureId}';
    case ChatLecturePage.reviewCards:
      return '$base/rcv/${t.lectureId}';
    case ChatLecturePage.transcript:
      final query = [
        if (t.startSid != null)
          'start_sid=${Uri.encodeQueryComponent(t.startSid!)}',
        if (t.endSid != null) 'end_sid=${Uri.encodeQueryComponent(t.endSid!)}',
      ].join('&');
      return '$base/v/${t.lectureId}/transcript${query.isEmpty ? '' : '?$query'}';
  }
}

/// コースのページの道順。
String chatCoursePath(String courseId) => '/home/courses/c/$courseId';
