import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/chat_composer_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';

ComposerMention draft(String label, String id) =>
    ComposerMention(label: label, target: DraftMention(id));

ComposerMention existing(
  String label,
  String id, [
  ChatAttachmentMode mode = ChatAttachmentMode.mention,
]) => ComposerMention(
  label: label,
  target: ExistingMention(attachmentId: id, mode: mode),
);

void main() {
  group('makeMentionLabel', () {
    test('adds @ and collapses whitespace', () {
      expect(makeMentionLabel('  my   notes.pdf ', const []), '@my notes.pdf');
    });

    test('falls back for an empty title', () {
      expect(makeMentionLabel('   ', const []), '@material');
    });

    test('shortens long titles on character boundaries', () {
      final label = makeMentionLabel('あ' * 60, const []);
      expect(label, '@${'あ' * 39}…');
    });

    test('numbers duplicates', () {
      expect(makeMentionLabel('A', ['@A']), '@A (2)');
      expect(makeMentionLabel('A', ['@A', '@A (2)']), '@A (3)');
    });
  });

  group('findMentionQuery', () {
    test('finds an @ at the start or after a space', () {
      expect(findMentionQuery('@ab', 3, const []), (start: 0, query: 'ab'));
      expect(findMentionQuery('see @ab', 7, const []), (start: 4, query: 'ab'));
    });

    test('ignores @ glued to a word (email addresses)', () {
      expect(findMentionQuery('a@b', 3, const []), isNull);
    });

    test('ignores a query that already has a space', () {
      expect(findMentionQuery('@ab cd', 6, const []), isNull);
    });

    test('ignores a label that is already inserted', () {
      expect(findMentionQuery('@notes ', 6, ['@notes']), isNull);
    });

    test('ignores out-of-range carets', () {
      expect(findMentionQuery('@a', 9, const []), isNull);
    });
  });

  group('mentionRanges', () {
    test('prefers the longer label where two overlap', () {
      final ranges = mentionRanges('@A (2) and @A', [
        draft('@A', 'a'),
        draft('@A (2)', 'b'),
      ]);
      expect(ranges.map((r) => (r.start, r.end)).toList(), [(0, 6), (11, 13)]);
      expect(ranges.first.mention.label, '@A (2)');
    });

    test('returns nothing when no label appears', () {
      expect(mentionRanges('hello', [draft('@A', 'a')]), isEmpty);
    });
  });

  group('toMessageContent', () {
    test('replaces labels with tokens and keeps unresolved ones as typed', () {
      final a = draft('@a.pdf', 'att1');
      final b = draft('@b.pdf', 'att2');
      final out = toMessageContent('compare @a.pdf with @b.pdf', [
        a,
        b,
      ], (m) => m == a ? 'real-a' : null);
      expect(out, 'compare ⟦att:real-a⟧ with @b.pdf');
    });
  });

  group('presentMentions / existingReferences', () {
    test('keeps only mentions that still appear', () {
      final a = existing('@a', '1');
      final b = existing('@b', '2');
      expect(presentMentions('only @a here', [a, b]), [a]);
    });

    test('merges duplicates, full wins', () {
      final refs = existingReferences([
        existing('@a', '1'),
        existing('@a (2)', '1', ChatAttachmentMode.full),
        existing('@b', '2'),
        draft('@c', 'c'),
      ]);
      expect(refs.map((r) => (r.attachmentId, r.mode)).toList(), [
        ('1', ChatAttachmentMode.full),
        ('2', ChatAttachmentMode.mention),
      ]);
    });
  });

  group('removeBrokenMention', () {
    final m = [draft('@notes.pdf', 'n')];

    test('removes the whole label when one character of it is deleted', () {
      final r = removeBrokenMention(
        'see @notes.pdf now',
        'see @notes.pd now',
        m,
      );
      expect(r, isNotNull);
      expect(r!.text, 'see  now');
      expect(r.caret, 4);
    });

    test('removes the whole label when the delete reaches into it', () {
      final r = removeBrokenMention('see @notes.pdf now', 'see @notes', m);
      // 後ろの " now" ごと消えた範囲 + 名前の欠け
      expect(r, isNotNull);
      expect(r!.text, 'see ');
    });

    test('leaves a delete that removes the label entirely', () {
      expect(removeBrokenMention('see @notes.pdf now', 'see  now', m), isNull);
    });

    test('leaves a delete away from any label', () {
      expect(
        removeBrokenMention('see @notes.pdf now', 'see @notes.pdf no', m),
        isNull,
      );
    });

    test('ignores insertions', () {
      expect(removeBrokenMention('abc', 'abcd', m), isNull);
    });
  });

  group('insertedText', () {
    test('returns the pasted segment', () {
      expect(insertedText('ab', 'aXYZb'), 'XYZ');
      expect(insertedText('', 'hello'), 'hello');
    });

    test('is empty when nothing was added', () {
      expect(insertedText('abc', 'ac'), '');
      expect(insertedText('abc', 'abc'), '');
    });
  });
}
