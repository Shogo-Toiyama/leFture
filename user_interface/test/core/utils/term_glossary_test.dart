import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/term_glossary.dart';
import 'package:lefture/domain/entities/keyword.dart';

Keyword _kw(
  String id,
  String keyword, {
  int topic = 1,
  String? definition = 'def',
}) => Keyword(
  id: id,
  topicNumber: topic,
  keyword: keyword,
  definition: definition,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

List<String> _marked(String text, TermGlossary g, {int? topic}) =>
    findTermMatches(
      text,
      g,
      <String>{},
      topic,
    ).map((m) => text.substring(m.start, m.end)).toList();

void main() {
  group('termFormsFor', () {
    test('splits the Japanese term and its parenthesised original', () {
      expect(
        termFormsFor('字句スコープ（lexical scoping）'),
        containsAll(['字句スコープ', 'lexical scoping']),
      );
    });

    test('splits compounds but drops short or hiragana-edged fragments', () {
      final forms = termFormsFor('回線交換とパケット交換');
      expect(forms, containsAll(['回線交換', 'パケット交換']));
      expect(termFormsFor('縄文・古墳時代の住居と高床建物'), isNot(contains('縄文')));
      expect(termFormsFor('問題としての文化'), isNot(contains('しての文化')));
    });

    test('keeps katakana words joined by a middle dot intact', () {
      expect(termFormsFor('マーク・アンド・スイープ'), isNot(contains('マーク')));
    });

    test('splits acronyms out of the parenthesised list', () {
      expect(
        termFormsFor('ドメインネームシステム (Domain Name System, DNS)'),
        containsAll(['ドメインネームシステム', 'domain name system', 'dns']),
      );
    });
  });

  group('findTermMatches', () {
    test('matches full-width and mixed-case text', () {
      final g = buildTermGlossary([_kw('a', 'DNS（Domain Name System）')]);
      expect(_marked('ＤＮＳはドメイン名を引く', g), ['ＤＮＳ']);
    });

    test('requires word boundaries for ASCII forms and allows plurals', () {
      final g = buildTermGlossary([
        _kw('a', '確認応答（ACK）'),
        _kw('b', 'ページテーブル（page table）'),
      ]);
      expect(_marked('the stack grows', g), isEmpty);
      expect(_marked('send an ACK now', g), ['ACK']);
      expect(_marked('two page tables here', g), ['page tables']);
    });

    test('marks each keyword only once per seen set', () {
      final g = buildTermGlossary([_kw('a', 'スタック（stack）')]);
      final seen = <String>{};
      expect(findTermMatches('スタックとスタック', g, seen, null), hasLength(1));
      expect(findTermMatches('またスタック', g, seen, null), isEmpty);
    });

    test('prefers the longest overlapping form', () {
      final g = buildTermGlossary([
        _kw('a', 'スタック（stack）'),
        _kw('b', 'スタックポインタ（stack pointer）'),
      ]);
      final matches = findTermMatches('スタックポインタを動かす', g, <String>{}, null);
      expect(matches.single.entry.id, 'b');
    });

    test('skips keywords without a definition', () {
      final g = buildTermGlossary([_kw('a', 'スタック', definition: null)]);
      expect(g.isEmpty, isTrue);
    });
  });
}
