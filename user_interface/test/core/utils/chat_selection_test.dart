import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/chat_selection.dart';
import 'package:lefture/domain/entities/chat.dart';

void main() {
  test('adds the text around the selection', () {
    const text = 'abcdefghij';
    final s = buildChatSelection(text, 3, 6, 'def');
    expect(s.text, 'def');
    expect(s.before, 'abc');
    expect(s.after, 'ghij');
    expect(s.screen, isNull);
  });

  test('limits the context to 200 characters each side', () {
    final text = '${'a' * 500}XYZ${'b' * 500}';
    final s = buildChatSelection(text, 500, 503, 'XYZ');
    expect(s.before!.length, chatSelectionContextChars);
    expect(s.after!.length, chatSelectionContextChars);
    expect(s.before, 'a' * 200);
    expect(s.after, 'b' * 200);
  });

  test('does not fail when the range is outside the text', () {
    final s = buildChatSelection('abc', -5, 99, 'abc');
    expect(s.before, '');
    expect(s.after, '');
    final t = buildChatSelection('abc', 5, 2, 'x');
    expect((t.before, t.after), ('abc', ''));
  });

  test('carries the page the selection was made on', () {
    final s = buildChatSelection(
      'abc',
      0,
      1,
      'a',
      screen: const ChatScreenRef(kind: 'deep_note', id: 'N1'),
    );
    expect(s.screen!.kind, 'deep_note');
    expect(s.screen!.id, 'N1');
  });
}
