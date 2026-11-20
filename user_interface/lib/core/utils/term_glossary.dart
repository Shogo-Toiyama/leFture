// lib/core/utils/term_glossary.dart
//
// 用語マーク: DeepNotes / ReviewCards の本文中に出てくる講義キーワードを見つけ、
// 薄くマークしてタップで定義を出すためのマッチャー。
// webapp/src/lib/termGlossary.ts と同じ規則で動かすこと。
//
// LLMは使わず、キーワード文字列から「本文に出てきそうな表記」をルールで作る:
//   - 全角英数字→半角、英字は小文字にそろえて比較する
//   - 「字句スコープ（lexical scoping）」は「字句スコープ」「lexical scoping」に分ける
//   - 「回線交換とパケット交換」のような複合語は「と・、,/ and or 及び」で分ける
// 意味は同じでも書き方がまったく違う語(静的スコープ↔字句スコープ)は拾えない。
//
// マークは元のテキストを一切変えない(TextSpanの装飾だけ)ので、
// アノテーションの座標系(annotation_text_utils.dart)には影響しない。

import 'package:lefture/core/utils/sid_citation.dart';
import 'package:lefture/domain/entities/keyword.dart';

class TermEntry {
  const TermEntry({
    required this.id,
    required this.keyword,
    required this.definition,
    required this.topicNumber,
  });

  final String id;
  final String keyword;
  final String definition;
  final int topicNumber;
}

class _TermForm {
  const _TermForm(this.form, this.entry, this.ascii);

  final String form;
  final TermEntry entry;

  /// 英数字だけの表記。前後が英数字でないこと(単語境界)を要求する。
  final bool ascii;
}

class TermGlossary {
  TermGlossary._(this.entries, this._forms);

  static final TermGlossary empty = TermGlossary._(const {}, const []);

  final Map<String, TermEntry> entries;

  /// 長い表記から順。
  final List<_TermForm> _forms;

  bool get isEmpty => _forms.isEmpty;

  /// MarkdownBodyのValueKeyに混ぜるための、内容が変わったときだけ変わる文字列。
  late final String cacheKey = entries.values
      .map((e) => '${e.id}:${e.keyword.hashCode}:${e.definition.hashCode}')
      .join('|');
}

/// 比較用に1文字ずつ畳み込む。文字数(UTF-16のコード単位数)を変えないことが重要で、
/// そうすれば畳み込んだ文字列で見つけた位置をそのまま元の文字列に使える。
String foldForMatch(String text) {
  final units = List<int>.of(text.codeUnits);
  for (var i = 0; i < units.length; i++) {
    var code = units[i];
    if (code >= 0xff01 && code <= 0xff5e) {
      code -= 0xfee0; // 全角ASCII→半角
    } else if (code == 0x3000) {
      code = 0x20; // 全角スペース
    }
    if (code >= 0x41 && code <= 0x5a) code += 0x20; // A-Z→a-z
    units[i] = code;
  }
  return String.fromCharCodes(units);
}

final _parenPattern = RegExp(r'^(.*?)\s*\((.+?)\)\s*$');
// 「・」はカタカナに挟まれていれば語の一部(マーク・アンド・スイープ)なので切らない。
final _splitPattern = RegExp(
  r'と|(?<![ァ-ヺー])・|・(?![ァ-ヺー])|、|,|/| and | or |および|及び',
);
final _asciiForm = RegExp(r"^[a-z0-9][a-z0-9 .+#'-]*$");
final _hiraganaOnly = RegExp(r'^[぀-ゟ]+$');
final _hiraganaEdge = RegExp(r'^[぀-ゟ]|[぀-ゟ]$');
final _digitsOnly = RegExp(r'^[0-9\s.]+$');
final _alnum = RegExp(r'[a-z0-9]');

bool _isUsableForm(String form, {required bool fromSplit}) {
  if (_digitsOnly.hasMatch(form) || _hiraganaOnly.hasMatch(form)) return false;
  if (_asciiForm.hasMatch(form)) return form.length >= 3;
  if (!fromSplit) return form.length >= 2;
  // 複合語を切った断片は一般語になりやすい(「縄文・古墳時代…」→「縄文」、
  // 「問題としての文化」→「しての文化」)ので、3文字以上で、ひらがなで始まり/終わらないものだけ。
  return form.length >= 3 && !_hiraganaEdge.hasMatch(form);
}

/// キーワード1つから、本文に当てる表記の候補を作る。
List<String> termFormsFor(String keyword) {
  final whole = foldForMatch(keyword).trim();
  final bases = <String>{whole};
  final paren = _parenPattern.firstMatch(whole);
  if (paren != null) {
    bases.add(paren.group(1)!.trim());
    bases.add(paren.group(2)!.trim());
  }

  final forms = <String>{};
  for (final base in bases) {
    if (_isUsableForm(base, fromSplit: false)) forms.add(base);
  }
  for (final base in bases) {
    for (final raw in base.split(_splitPattern)) {
      final piece = raw.trim();
      if (piece != base && _isUsableForm(piece, fromSplit: true)) {
        forms.add(piece);
      }
    }
  }
  return forms.toList();
}

TermGlossary buildTermGlossary(List<Keyword> keywords) {
  if (keywords.isEmpty) return TermGlossary.empty;
  final entries = <String, TermEntry>{};
  final forms = <_TermForm>[];
  final claimed = <String>{};

  // 同じ表記を2つのキーワードが作った場合は、先に来た(トピック順で早い)方に寄せる。
  final sorted = [...keywords]
    ..sort((a, b) => a.topicNumber.compareTo(b.topicNumber));
  for (final kw in sorted) {
    final keyword = kw.keyword?.trim() ?? '';
    final definition = kw.definition == null
        ? ''
        : stripSidCitations(kw.definition!).trim();
    if (keyword.isEmpty || definition.isEmpty) continue; // 出すものがない

    final entry = TermEntry(
      id: kw.id,
      keyword: keyword,
      definition: definition,
      topicNumber: kw.topicNumber,
    );
    entries[entry.id] = entry;
    for (final form in termFormsFor(keyword)) {
      if (!claimed.add(form)) continue;
      forms.add(_TermForm(form, entry, _asciiForm.hasMatch(form)));
    }
  }

  forms.sort((a, b) => b.form.length.compareTo(a.form.length));
  return TermGlossary._(entries, forms);
}

class TermMatch {
  const TermMatch(this.start, this.end, this.entry);

  final int start;
  final int end;
  final TermEntry entry;
}

/// テキスト1つの中のマッチを返す(重なりなし、位置順)。
/// 重なったら長い表記を優先し、同じ長さなら[topicNumber]のキーワードを優先する。
/// [seen]にあるキーワードは飛ばし、マークしたものを追加する(=範囲内で最初の1回だけ)。
List<TermMatch> findTermMatches(
  String text,
  TermGlossary glossary,
  Set<String> seen,
  int? topicNumber,
) {
  if (glossary.isEmpty || text.isEmpty) return const [];
  final folded = foldForMatch(text);
  bool isAlnumAt(int i) =>
      i >= 0 && i < folded.length && _alnum.hasMatch(folded[i]);

  final candidates = <TermMatch>[];
  for (final f in glossary._forms) {
    var from = 0;
    while (true) {
      final at = folded.indexOf(f.form, from);
      if (at < 0) break;
      from = at + 1;
      var end = at + f.form.length;
      if (f.ascii) {
        if (isAlnumAt(at - 1)) continue;
        // 複数形(page table → page tables)までは同じ語として含める
        if (end < folded.length && folded[end] == 's' && !isAlnumAt(end + 1)) {
          end += 1;
        }
        if (isAlnumAt(end)) continue;
      }
      candidates.add(TermMatch(at, end, f.entry));
    }
  }

  candidates.sort((a, b) {
    final byLength = (b.end - b.start).compareTo(a.end - a.start);
    if (byLength != 0) return byLength;
    final aHome = a.entry.topicNumber == topicNumber ? 0 : 1;
    final bHome = b.entry.topicNumber == topicNumber ? 0 : 1;
    if (aHome != bHome) return aHome.compareTo(bHome);
    return a.start.compareTo(b.start);
  });

  final taken = <TermMatch>[];
  for (final c in candidates) {
    if (taken.any((t) => c.start < t.end && t.start < c.end)) continue;
    taken.add(c);
  }
  taken.sort((a, b) => a.start.compareTo(b.start));

  final result = <TermMatch>[];
  for (final m in taken) {
    if (!seen.add(m.entry.id)) continue;
    result.add(m);
  }
  return result;
}
