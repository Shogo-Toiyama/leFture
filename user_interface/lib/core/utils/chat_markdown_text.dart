// lib/core/utils/chat_markdown_text.dart
//
// AIチャットの回答本文(Markdown)の下ごしらえ。webappの webapp/src/lib/markdownText.ts と
// chatCitations.ts を移したもの(同じ入力は同じ出力になる)。
//
// 流れ: prepareMath → linkifyCitations → (flutter_markdownで描く)
// 太字の直し(fixBoldPunctuationSpacing)は、アプリ全体で使っている CjkSafeBoldSyntax
// (markdown_bold_syntax.dart)が同じ問題を解いているので移していない。

/// ```…``` と `…` を境界にして、コード以外の部分だけ処理する。
final _codeSplit = RegExp(r'(```[\s\S]*?(?:```|$)|`[^`\n]*`)');

/// 整形処理が触ってはいけない部分(コード・数式・エスケープされた\$)。
/// 数式は prepareMath を通した後の形($$…$$ / $…$。値段の $ は \$ にエスケープ済み)を前提にしている。
final _protectedSplit = RegExp(
  r'(```[\s\S]*?(?:```|$)|`[^`\n]*`|\\\$|\$\$[\s\S]*?\$\$|\$[^$\n]+?\$)',
);

/// [text]を、[pattern]に当たる部分(protected=true)と、それ以外に分ける。
/// JavaScriptの split(キャプチャ付き)と違い、Dartのsplitは当たった部分を返さないので自前で分ける。
List<({String text, bool protected})> _splitProtected(
  String text,
  RegExp pattern,
) {
  final parts = <({String text, bool protected})>[];
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      parts.add((text: text.substring(last, m.start), protected: false));
    }
    parts.add((text: m.group(0)!, protected: true));
    last = m.end;
  }
  if (last < text.length) {
    parts.add((text: text.substring(last), protected: false));
  }
  return parts;
}

// ---------------------------------------------------------------------------
// 数式
// ---------------------------------------------------------------------------

/// 回答役のLaTeXを、数式として読める形にそろえる(コードの中は触らない)。
/// - `\(…\)` → `$…$`、`\[…\]` → `$$…$$`(よくある書き方。Markdownの数式は$しか読まない)
/// - 数式ではない $(値段の「$5 と $10」など)を `\$` にエスケープする。判定はPandocと同じ:
///   開きの $ の直後が空白でなく、閉じの $ の直前が空白でなく、閉じの直後が数字でないときだけ数式。
/// 生成中に閉じがまだ届いていない `$x` は、届くまでは文字のまま表示される。
String prepareMath(String markdown) {
  if (markdown.isEmpty) return markdown;
  final out = StringBuffer();
  for (final part in _splitProtected(markdown, _codeSplit)) {
    out.write(part.protected ? part.text : _prepareMathSegment(part.text));
  }
  return out.toString();
}

final _whitespace = RegExp(r'\s');
final _digit = RegExp(r'\d');

String _prepareMathSegment(String source) {
  // 別行の数式は $$ を前後の行に置いた形にする(1行に $$ と式があると、行内の数式として描かれる)。
  // 1行だけで書かれた $$…$$ も同じ形にそろえる
  final text = source
      .replaceAllMapped(
        RegExp(r'\\\[([\s\S]+?)\\\]'),
        (m) => '\n\$\$\n${m[1]!.trim()}\n\$\$\n',
      )
      .replaceAllMapped(
        RegExp(r'^[ \t]*\$\$([^\n$]+?)\$\$[ \t]*$', multiLine: true),
        (m) => '\$\$\n${m[1]!.trim()}\n\$\$',
      )
      .replaceAllMapped(
        RegExp(r'\\\(([^\n]+?)\\\)'),
        (m) => '\$${m[1]!.trim()}\$',
      );

  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (ch == r'\' && i + 1 < text.length && text[i + 1] == r'$') {
      out.write(r'\$');
      i += 2;
      continue;
    }
    if (ch != r'$') {
      out.write(ch);
      i += 1;
      continue;
    }
    if (i + 1 < text.length && text[i + 1] == r'$') {
      // 別行の数式 $$…$$。閉じが無ければ文字のまま
      final close = text.indexOf(r'$$', i + 2);
      if (close > i + 2) {
        out.write(text.substring(i, close + 2));
        i = close + 2;
      } else {
        out.write(r'\$\$');
        i += 2;
      }
      continue;
    }
    // 行内の数式 $…$: 開きの直後が空白でなければ、同じ行の次の $ が閉じとして正しいかを見る
    if (i + 1 < text.length && !_whitespace.hasMatch(text[i + 1])) {
      var j = i + 1;
      while (j < text.length && text[j] != '\n' && text[j] != r'$') {
        j += 1;
      }
      final afterClose = j + 1 < text.length ? text[j + 1] : '';
      if (j < text.length &&
          text[j] == r'$' &&
          !_whitespace.hasMatch(text[j - 1]) &&
          !_digit.hasMatch(afterClose) &&
          afterClose != r'$') {
        out.write(text.substring(i, j + 1));
        i = j + 1;
        continue;
      }
    }
    out.write(r'\$');
    i += 1;
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// 出典の引用
// ---------------------------------------------------------------------------

// 3 / 3.5 / 3.5-7 / W1.2 の1つ分(括弧の中身)。範囲の後ろ側に出典番号を繰り返す書き方(3.5-3.7)も許す。
final _citeItem = RegExp(
  r'^\s*(W?\d{1,2})(?:\s*\.\s*(\d{1,3})(?:\s*[-–]\s*(?:W?\d{1,2}\s*\.\s*)?(\d{1,3}))?)?\s*$',
);

// ⟦…⟧(今の形) と [...](昔の形・回答役の癖)。英数字の直後の [..](添字 a[1])は _isIndexLike で除く
final _cite = RegExp(
  r'([ \t]?)(?:⟦([^⟦⟧\n]{1,60})⟧|\[([^\[\]\n]{1,60})\](?!\())',
);

final _indexChar = RegExp(r'[A-Za-z0-9_]');

/// 直前が英数字(a[1] のような添字)なら引用ではない。
bool _isIndexLike(String text, int offset) =>
    offset > 0 && _indexChar.hasMatch(text[offset - 1]);

/// 回答本文の引用を、Markdown上で押せるリンクに置き換える。表示は出典の番号だけ(⟦3.5⟧ も「3」)。
///   ⟦3⟧    → [3](#cite-3)
///   ⟦3.5⟧  → [3](#cite-3~5)      ⟦3.5-7⟧ → [3](#cite-3~5-7)
/// 同じ出典が続けて並んだ ⟦3.5⟧⟦3.9⟧ は1つにまとめる → [3](#cite-3~5,9)。
/// 本文は先に prepareMath を通しておくこと(数式の中を触らないため)。
/// バックエンドの normalize_citations と同じ整理もここでする(修正前に保存された回答と、生成中の表示のため):
/// - ⟦2.5, W1.3⟧ は1つずつに分ける。実在しない出典の番号は消す。
/// - 昔の形 [3] / [3.5] も読む。こちらは区間・添字と紛れるので、数字だけのまとまりは全部が実在する出典番号の
///   ときだけ引用とみなし、[0.5] のような出典番号でない数の区切りつき表記は残す。
/// コード・数式の中と、英数字の直後の [..](配列の添字 a[1] 等)は触らない。
String linkifyCitations(String markdown, Set<String> refs) {
  if (markdown.isEmpty) return markdown;
  final out = StringBuffer();
  for (final part in _splitProtected(markdown, _protectedSplit)) {
    out.write(part.protected ? part.text : _linkifySegment(part.text, refs));
  }
  return out.toString();
}

String _linkifySegment(String segment, Set<String> refs) {
  final linked = segment.replaceAllMapped(_cite, (match) {
    final whole = match[0]!;
    final space = match[1]!;
    final double = match[2];
    final legacy = match[3];
    final isLegacy = double == null;
    if (isLegacy && _isIndexLike(match.input, match.start + space.length)) {
      return whole;
    }

    final rawItems = (isLegacy ? legacy! : double).split(RegExp(r'[,、，]'));
    final parsed = <RegExpMatch>[];
    for (final raw in rawItems) {
      final item = _citeItem.firstMatch(raw);
      if (item == null) return whole; // 引用ではない括弧
      parsed.add(item);
    }
    if (isLegacy) {
      final dotted = parsed.any((m) => m[2] != null);
      final hasWeb = parsed.any((m) => m[1]!.startsWith('W'));
      if (parsed.length > 1 &&
          !dotted &&
          !hasWeb &&
          !parsed.every((m) => refs.contains(m[1]))) {
        return whole;
      }
      if (parsed.length == 1 &&
          dotted &&
          !hasWeb &&
          !refs.contains(parsed[0][1])) {
        return whole;
      }
    }
    final links = parsed.where((m) => refs.contains(m[1])).map((m) {
      final String spec;
      if (m[2] != null) {
        spec = m[3] != null && m[3] != m[2] ? '${m[2]}-${m[3]}' : m[2]!;
      } else {
        spec = '';
      }
      return '[${m[1]}](#cite-${m[1]}${spec.isEmpty ? '' : '~$spec'})';
    }).join();
    return links.isEmpty ? '' : space + links;
  });

  // 同じ出典が続けて並んだものを1つにまとめる
  final mergePattern = RegExp(
    r'\[(W?\d{1,2})\]\(#cite-\1(?:~([\d,-]+))?\)\[\1\]\(#cite-\1(?:~([\d,-]+))?\)',
  );
  var merged = linked;
  for (var prev = ''; prev != merged;) {
    prev = merged;
    merged = merged.replaceAllMapped(mergePattern, (m) {
      final specs = <String>{
        for (final s in [m[2], m[3]].whereType<String>().join(',').split(','))
          if (s.isNotEmpty) s,
      }.join(',');
      return '[${m[1]}](#cite-${m[1]}${specs.isEmpty ? '' : '~$specs'})';
    });
  }
  return merged;
}

/// "#cite-3" → (ref: "3", specs: [])、"#cite-W1~2" → (ref: "W1", specs: ["2"])、
/// "#cite-3~5,9-10" → (ref: "3", specs: ["5", "9-10"])。引用リンクでなければnull。
/// specs は ChatCitation.passages のキー(押された引用の区切り)。
({String ref, List<String> specs})? parseCitationHref(String? href) {
  if (href == null) return null;
  final m = RegExp(r'^#cite-(W?\d{1,2})(?:~([\d,-]+))?$').firstMatch(href);
  if (m == null) return null;
  return (
    ref: m[1]!,
    specs: m[2] == null
        ? const []
        : [
            for (final s in m[2]!.split(','))
              if (s.isNotEmpty) s,
          ],
  );
}

/// 回答のMarkdownをコピー用にする: 出典の印(⟦3⟧・[3]など)だけを取り除き、ほかの本文はそのまま残す。
/// 画面に出る出典番号と同じ判定(linkifyCitations)を通すので、配列の添字 a[1] などは消えない。
String stripCitationMarkers(String markdown, Set<String> refs) =>
    linkifyCitations(
      markdown,
      refs,
    ).replaceAll(RegExp(r'[ \t]?\[(?:W?\d{1,2})\]\(#cite-[^)]*\)'), '');

/// 出典の区切り(Markdownの1ブロックや1文)を、ハイライトのある平文として見せるための整形。
/// 区切りはブロックの途中で切れていることがあり(**の片方だけ等)、Markdownとして描くと崩れるので、
/// 見出し・箇条書き・引用の記号と、強調・コードの記号を外す。改行は残す。
String markdownToPlainText(String markdown) {
  if (markdown.isEmpty) return markdown;
  return markdown
      .replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'^[ \t]*>[ \t]?', multiLine: true), '')
      .replaceAll(
        RegExp(r'^[ \t]*(?:[-*+]|\d+\.)[ \t]+', multiLine: true),
        '• ',
      )
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAllMapped(RegExp(r'\[([^\]\n]+)\]\((?:[^)\s]+)\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
