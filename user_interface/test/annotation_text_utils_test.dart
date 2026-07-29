import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/annotation_text_utils.dart';

void main() {
  group('findSourceCitation (食い込み許容 & 広範囲選択ボトムシート情報のテスト)', () {
    const rawText =
        'This is section 1 long text content.⟦s000001⟧ This is section 2 long text content.⟦s000002⟧ This is section 3 long text content.⟦s000003⟧';

    test('単一区間内の選択は正常に直後の引用を取得できる', () {
      final citation = findSourceCitation(rawText, 0, 15);
      expect(citation, isNotNull);
      expect(citation!.sids, equals([1]));
    });

    test('境界の食い込みがわずか（3文字）の場合、メイン領域の引用を自動採用する', () {
      // section 1 の末尾 "nt." (3文字) + section 2 の頭 "This is section 2" (17文字)
      // 食い込み(left): 3文字 (<= 5文字) -> 許容！ メインは section 2 なので s000002 が採用される
      final citation = findSourceCitation(rawText, 33, 53);
      expect(citation, isNotNull);
      expect(citation!.sids, equals([2]));
    });

    test('2つのマーカー跨ぎで、前後両端の食い込みがわずか（各3文字）の場合、真ん中の区間を自動採用する', () {
      // section 1 の末尾 "nt." (3文字) + section 2 全体 + section 3 の頭 "Thi" (3文字)
      // 食い込み front: 3文字 (<= 5), back: 3文字 (<= 5)
      // 真ん中の section 2 の引用 s000002 が自動採用される！
      final citation = findSourceCitation(rawText, 33, 73);
      expect(citation, isNotNull);
      expect(citation!.sids, equals([2]));
    });

    test('食い込みが大きく（8文字かつ25%超）、境界を超えている場合はSelectionTooBroadExceptionを投げ、ボトムシート用オプションを含める', () {
      // section 1 の末尾8文字 + section 2 の頭8文字 (合計16文字, minorLen = 8 > 5, 8/16 = 50% > 15%)
      try {
        findSourceCitation(rawText, 28, 44);
        fail('Should throw SelectionTooBroadException');
      } on SelectionTooBroadException catch (e) {
        expect(e.options.length, equals(2));
        expect(e.options[0].citation.sids, equals([1]));
        expect(e.options[1].citation.sids, equals([2]));
        // セクション内ハイライト位置がセットされているか検証
        expect(e.options[0].selectedStartInSection, isNotNull);
        expect(e.options[1].selectedStartInSection, isNotNull);
      }
    });

    test('3つの引用マーカーが含まれる広範囲選択はSelectionTooBroadExceptionを投げ、該当するすべてのオプションを含める', () {
      try {
        findSourceCitation(rawText, 0, 100);
        fail('Should throw SelectionTooBroadException');
      } on SelectionTooBroadException catch (e) {
        expect(e.options.length, equals(3));
      }
    });
  });
}
