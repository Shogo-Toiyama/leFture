import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';

void main() {
  group('parseSidCitations', () {
    test('正常な単体SID', () {
      final result = parseSidCitations('Hello ⟦s000042⟧ world');
      expect(result.length, 1);
      expect(result.first.sids, [42]);
      expect(result.first.sidStrings, ['s000042']);
    });

    test('正常な範囲', () {
      final result = parseSidCitations('text ⟦s000010-s000013⟧');
      expect(result.first.sids, [10, 11, 12, 13]);
    });

    test('カンマ区切り複数 + 範囲の混在', () {
      final result = parseSidCitations('⟦s000001, s000005-s000007, s000020⟧');
      expect(result.first.sids, [1, 5, 6, 7, 20]);
    });

    test('大文字S・桁数不足の修復', () {
      final result = parseSidCitations('⟦S42-s0045⟧');
      expect(result.first.sids, [42, 43, 44, 45]);
      expect(result.first.sidStrings.first, 's000042');
    });

    test('全角カンマ・enダッシュ・emダッシュの修復', () {
      final result = parseSidCitations('⟦s000001，s000003–s000005⟧ and ⟦s000010—s000011⟧');
      expect(result[0].sids, [1, 3, 4, 5]);
      expect(result[1].sids, [10, 11]);
    });

    test('閉じカッコ忘れの修復 (文末まで)', () {
      final result = parseSidCitations('citation at end ⟦s000009');
      expect(result.length, 1);
      expect(result.first.sids, [9]);
    });

    test('閉じカッコ忘れの修復 (直後に通常テキスト)', () {
      final result = parseSidCitations('open ⟦s000003-s000004 and more text here');
      expect(result.first.sids, [3, 4]);
    });

    test('逆順範囲の救済', () {
      final result = parseSidCitations('⟦s000010-s000008⟧');
      expect(result.first.sids, [8, 9, 10]);
    });

    test('SIDが無いカッコは引用扱いしない', () {
      final result = parseSidCitations('math ⟦x + y⟧ notation');
      expect(result, isEmpty);
    });

    test('複数の引用', () {
      final result = parseSidCitations('a ⟦s000001⟧ b ⟦s000002⟧ c');
      expect(result.length, 2);
    });
  });

  group('stripSidCitations', () {
    test('引用と直前スペースを除去', () {
      expect(
        stripSidCitations('stored across a network ⟦s000011-s000014⟧.'),
        'stored across a network.',
      );
    });

    test('複数引用の除去', () {
      expect(
        stripSidCitations('File owner ⟦s000020⟧ and timestamps ⟦s000021⟧ remain.'),
        'File owner and timestamps remain.',
      );
    });

    test('閉じ忘れ引用の除去', () {
      expect(
        stripSidCitations('some claim ⟦s000009'),
        'some claim',
      );
    });

    test('引用が無ければそのまま', () {
      expect(stripSidCitations('plain text'), 'plain text');
    });

    test('改行は保持される', () {
      expect(
        stripSidCitations('line one ⟦s000001⟧\nline two'),
        'line one\nline two',
      );
    });
  });
}
