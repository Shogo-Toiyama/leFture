import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/chat_markdown_text.dart';

void main() {
  group('prepareMath', () {
    test(r'丸括弧と角括弧のLaTeXは、$ の数式になる', () {
      expect(prepareMath(r'値は \(x^2\) です'), r'値は $x^2$ です');
      expect(prepareMath(r'\[a+b\]'), '\n\$\$\na+b\n\$\$\n');
    });

    test(r'1行の $$…$$ は前後の行に $$ を置いた形にそろう', () {
      expect(prepareMath(r'$$a+b$$'), '\$\$\na+b\n\$\$');
    });

    test(r'値段の $ は数式にせずエスケープする', () {
      expect(prepareMath(r'$5 と $10 です'), r'\$5 と \$10 です');
    });

    test('ふつうの行内の数式は残る', () {
      expect(prepareMath(r'式 $x+1$ と $y$ です'), r'式 $x+1$ と $y$ です');
    });

    test('閉じの直後が数字なら数式ではない', () {
      expect(prepareMath(r'$a$1'), r'\$a\$1');
    });

    test(r'閉じがまだ届いていない $x は文字のまま', () {
      expect(prepareMath(r'式 $x+1'), r'式 \$x+1');
    });

    test('コードの中は触らない', () {
      expect(
        prepareMath(
          r'`$5 と $10` と '
          r'$5',
        ),
        r'`$5 と $10` と '
        r'\$5',
      );
      expect(prepareMath('```\n\$5\n```'), '```\n\$5\n```');
    });

    test(r'すでにエスケープされた \$ はそのまま', () {
      expect(prepareMath(r'\$5'), r'\$5');
    });

    test('空文字はそのまま', () {
      expect(prepareMath(''), '');
    });
  });

  group('linkifyCitations', () {
    final refs = {'1', '2', '3', 'W1'};

    test('⟦3⟧ は押せるリンクになる', () {
      expect(linkifyCitations('これは大事⟦3⟧です', refs), 'これは大事[3](#cite-3)です');
    });

    test('区切りつき ⟦3.5⟧ ⟦3.5-7⟧', () {
      expect(linkifyCitations('A⟦3.5⟧', refs), 'A[3](#cite-3~5)');
      expect(linkifyCitations('A⟦3.5-7⟧', refs), 'A[3](#cite-3~5-7)');
      expect(linkifyCitations('A⟦3.5-3.7⟧', refs), 'A[3](#cite-3~5-7)');
    });

    test('同じ出典が続けて並んだら1つにまとめる', () {
      expect(linkifyCitations('A⟦3.5⟧⟦3.9⟧', refs), 'A[3](#cite-3~5,9)');
    });

    test('1つの括弧に複数あれば1つずつに分け、実在しない番号は消す', () {
      expect(linkifyCitations('A⟦1, 2⟧', refs), 'A[1](#cite-1)[2](#cite-2)');
      expect(linkifyCitations('A⟦1, 9⟧', refs), 'A[1](#cite-1)');
      expect(linkifyCitations('A⟦9⟧B', refs), 'AB');
    });

    test('Webの出典 W1', () {
      expect(linkifyCitations('A⟦W1⟧', refs), 'A[W1](#cite-W1)');
    });

    test('昔の形 [3] も読むが、配列の添字 a[1] は触らない', () {
      expect(linkifyCitations('これは大事[3]です', refs), 'これは大事[3](#cite-3)です');
      expect(linkifyCitations('A[3]', refs), 'A[3]'); // 英数字の直後は添字
      expect(linkifyCitations('a[1] を読む', refs), 'a[1] を読む');
    });

    test('昔の形で、出典番号でない数の区切りつき表記は残す', () {
      expect(linkifyCitations('値は[0.5]です', refs), '値は[0.5]です');
    });

    test('リンクの [text](url) は触らない', () {
      expect(
        linkifyCitations('[3](https://example.com)', refs),
        '[3](https://example.com)',
      );
    });

    test('コード・数式の中は触らない', () {
      expect(linkifyCitations('`⟦3⟧` と \$⟦3⟧\$', refs), '`⟦3⟧` と \$⟦3⟧\$');
    });

    test('出典が無ければ印だけ消える', () {
      expect(linkifyCitations('A⟦3⟧', {}), 'A');
    });
  });

  group('parseCitationHref', () {
    test('番号と区切りを読む', () {
      var parsed = parseCitationHref('#cite-3')!;
      expect(parsed.ref, '3');
      expect(parsed.specs, isEmpty);
      parsed = parseCitationHref('#cite-W1~2')!;
      expect(parsed.ref, 'W1');
      expect(parsed.specs, ['2']);
      parsed = parseCitationHref('#cite-3~5,9-10')!;
      expect(parsed.ref, '3');
      expect(parsed.specs, ['5', '9-10']);
    });

    test('引用リンクでなければnull', () {
      expect(parseCitationHref('https://example.com'), isNull);
      expect(parseCitationHref(null), isNull);
      expect(parseCitationHref('#cite-'), isNull);
    });
  });

  group('stripCitationMarkers', () {
    test('出典の印だけを取り除き、本文はそのまま残す', () {
      expect(
        stripCitationMarkers('二分ヒープは木 ⟦3.5⟧です。a[1] も同じ', {'3'}),
        '二分ヒープは木です。a[1] も同じ',
      );
    });
  });

  group('markdownToPlainText', () {
    test('見出し・箇条書き・強調の記号を外す', () {
      expect(
        markdownToPlainText('## 見出し\n- **強い** 項目\n> 引用'),
        '見出し\n• 強い 項目\n引用',
      );
    });
  });
}
