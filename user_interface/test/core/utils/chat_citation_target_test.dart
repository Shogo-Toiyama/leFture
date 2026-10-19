import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/chat_citation_target.dart';
import 'package:lefture/domain/entities/chat.dart';

ChatCitation cite(
  String type, {
  String? lectureId,
  String? courseId,
  String? threadId,
  String? url,
  Map<String, dynamic> metadata = const {},
}) => ChatCitation(
  ref: '1',
  sourceType: type,
  lectureId: lectureId,
  courseId: courseId,
  threadId: threadId,
  url: url,
  label: 'C / L / D',
  metadata: metadata,
);

void main() {
  group('chatCitationTarget', () {
    test('web pages open as a url, only for http(s)', () {
      final t = chatCitationTarget(cite('web', url: 'https://example.com/a'));
      expect((t as CitationWebTarget).url, 'https://example.com/a');
      expect(
        chatCitationTarget(cite('web', url: 'javascript:alert(1)')),
        isNull,
      );
      expect(chatCitationTarget(cite('web')), isNull);
    });

    test('attachments only preview', () {
      expect(
        chatCitationTarget(cite('chat_attachment', lectureId: 'L')),
        isNull,
      );
    });

    test('a past chat opens its thread, a course opens the course', () {
      expect(
        (chatCitationTarget(cite('chat_turn', threadId: 'T'))
                as CitationThreadTarget)
            .threadId,
        'T',
      );
      expect(chatCitationTarget(cite('chat_turn')), isNull);
      expect(
        (chatCitationTarget(cite('course', courseId: 'C'))
                as CitationCourseTarget)
            .courseId,
        'C',
      );
    });

    test('lecture-based sources go to their page', () {
      CitationLectureTarget t(
        String type, {
        Map<String, dynamic> m = const {},
      }) =>
          chatCitationTarget(
                cite(type, lectureId: 'L', courseId: 'C', metadata: m),
              )
              as CitationLectureTarget;
      expect(t('deep_note').page, ChatLecturePage.deepNotes);
      expect(t('review_card').page, ChatLecturePage.reviewCards);
      expect(t('transcript_topic').page, ChatLecturePage.transcript);
      expect(t('keyword').page, ChatLecturePage.lecture);
      expect(t('announcement').page, ChatLecturePage.lecture);
    });

    test('without a lecture there is nowhere to go', () {
      expect(chatCitationTarget(cite('announcement')), isNull);
    });

    test('a transcript sentence range becomes start/end', () {
      final t =
          chatCitationTarget(
                cite(
                  'transcript_topic',
                  lectureId: 'L',
                  metadata: {'sentence_range': '12 - 18'},
                ),
              )
              as CitationLectureTarget;
      expect((t.startSid, t.endSid), ('12', '18'));
      final one =
          chatCitationTarget(
                cite(
                  'transcript_topic',
                  lectureId: 'L',
                  metadata: {'sentence_range': '12'},
                ),
              )
              as CitationLectureTarget;
      expect((one.startSid, one.endSid), ('12', null));
    });
  });

  group('chatCitationPath', () {
    CitationLectureTarget target(
      ChatLecturePage p, {
      String? course,
      String? s,
      String? e,
    }) => CitationLectureTarget(
      page: p,
      lectureId: 'L1',
      courseId: course,
      startSid: s,
      endSid: e,
    );

    test('builds the nested routes', () {
      expect(
        chatCitationPath(target(ChatLecturePage.lecture, course: 'C1'), null),
        '/home/courses/c/C1/v/L1',
      );
      expect(
        chatCitationPath(target(ChatLecturePage.deepNotes), 'C2'),
        '/home/courses/c/C2/dn/L1',
      );
      expect(
        chatCitationPath(
          target(ChatLecturePage.reviewCards, course: 'C1'),
          null,
        ),
        '/home/courses/c/C1/rcv/L1',
      );
      expect(
        chatCitationPath(
          target(ChatLecturePage.transcript, course: 'C1', s: '12', e: '18'),
          null,
        ),
        '/home/courses/c/C1/v/L1/transcript?start_sid=12&end_sid=18',
      );
      expect(
        chatCitationPath(
          target(ChatLecturePage.transcript, course: 'C1'),
          null,
        ),
        '/home/courses/c/C1/v/L1/transcript',
      );
    });

    test('is null without a course', () {
      expect(chatCitationPath(target(ChatLecturePage.lecture), null), isNull);
    });

    test('the citation course wins over the looked-up one', () {
      expect(
        chatCitationPath(
          target(ChatLecturePage.lecture, course: 'C1'),
          'OTHER',
        ),
        '/home/courses/c/C1/v/L1',
      );
    });
  });
}
