/// SID引用記法のパース/修復/除去ヘルパー。
///
/// バックエンドのLLMが生成するコンテンツ(deep_notes, review_cards, summary等)には
/// `⟦s000011-s000014⟧` のような形式でトランスクリプト文への引用が埋め込まれる。
///
/// 正規のフォーマット:
///   - 二重角カッコ ⟦ (U+27E6) と ⟧ (U+27E7) で囲まれる
///   - 中身は小文字の `s` + 0埋め6桁の数字 (例: s000042)
///   - 複数はカンマ区切り: ⟦s000010, s000015⟧
///   - 範囲はハイフン区切り: ⟦s000010-s000015⟧
///
/// ただしLLM出力なので揺れがある前提でパースする:
///   - 閉じカッコの欠落 (⟦s000010 のまま文末/次のカッコまで)
///   - 大文字の S
///   - 数字が6桁でない (s42, s0042 など)
///   - 全角/類似Unicode文字のカンマ・ハイフン (、 ， – — − ‐ など)
///   - 類似の角カッコ (〚〛 [[ ]] など)
library;

/// 1つの引用グループ(⟦...⟧ 1個分)のパース結果。
class SidCitation {
  const SidCitation({
    required this.raw,
    required this.start,
    required this.end,
    required this.sids,
  });

  /// 元テキスト内でマッチした生の文字列 (例: "⟦s000010-s000012⟧")
  final String raw;

  /// 元テキスト内での開始オフセット
  final int start;

  /// 元テキスト内での終了オフセット (exclusive)
  final int end;

  /// 展開済みのSID番号リスト (範囲は展開される)。
  /// 例: ⟦s000010-s000012⟧ → [10, 11, 12]
  final List<int> sids;

  /// "s000010" 形式の文字列リスト
  List<String> get sidStrings => sids.map(formatSid).toList();
}

/// SID番号を正規の "s000042" 形式にフォーマットする。
String formatSid(int number) => 's${number.toString().padLeft(6, '0')}';

// 開きカッコとして受け付ける表記 (揺れ含む)
const _openBrackets = ['⟦', '〚', '[['];
// 閉じカッコとして受け付ける表記 (揺れ含む)
const _closeBrackets = ['⟧', '〛', ']]'];

// ハイフン/ダッシュとして受け付ける文字 (ASCII - / 各種Unicodeダッシュ / 全角)
const _dashChars = '-‐‑‒–—―−－~〜～';
// カンマとして受け付ける文字 (ASCII , / 全角 / 読点 / セミコロン)
const _commaChars = ',，、;；';

/// 中身の "s000010-s000012, s000020" のような文字列をSID番号リストに展開する。
/// パースできない断片は黙って読み飛ばす(全体を失敗させない)。
List<int> _parseSidBody(String body) {
  final sids = <int>[];

  // カンマ類で分割
  final parts = body.split(RegExp('[$_commaChars]'));
  final sidPattern = RegExp(r'[sS]\s*0*(\d{1,6})');

  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;

    // ダッシュ類が含まれていれば範囲として扱う
    final rangeSplit = trimmed.split(RegExp('[$_dashChars]'));
    if (rangeSplit.length >= 2) {
      final fromMatch = sidPattern.firstMatch(rangeSplit.first);
      final toMatch = sidPattern.firstMatch(rangeSplit.last);
      if (fromMatch != null && toMatch != null) {
        var from = int.parse(fromMatch.group(1)!);
        var to = int.parse(toMatch.group(1)!);
        if (from > to) {
          // 逆順は入れ替えて救済
          final tmp = from;
          from = to;
          to = tmp;
        }
        // 異常に広い範囲はLLMの暴走とみなして端点のみ採用
        if (to - from > 5000) {
          sids..add(from)..add(to);
        } else {
          for (var i = from; i <= to; i++) {
            sids.add(i);
          }
        }
        continue;
      }
    }

    // 単体SID
    final single = sidPattern.firstMatch(trimmed);
    if (single != null) {
      sids.add(int.parse(single.group(1)!));
    }
  }

  return sids;
}

/// テキスト中の全SID引用を検出してパースする。
///
/// 閉じカッコが無い場合は、開きカッコ以降の「SID引用として妥当な部分」までを
/// 引用とみなして自動修復する。
List<SidCitation> parseSidCitations(String text) {
  final results = <SidCitation>[];

  final openPattern = RegExp(_openBrackets.map(RegExp.escape).join('|'));
  final closePattern = RegExp(_closeBrackets.map(RegExp.escape).join('|'));

  var searchStart = 0;
  while (searchStart < text.length) {
    final openMatch = openPattern.firstMatch(text.substring(searchStart));
    if (openMatch == null) break;

    final openStart = searchStart + openMatch.start;
    final bodyStart = searchStart + openMatch.end;

    final closeMatch = closePattern.firstMatch(text.substring(bodyStart));
    // 次の開きカッコの位置 (閉じ忘れ判定用)
    final nextOpenMatch = openPattern.firstMatch(text.substring(bodyStart));

    int bodyEnd;
    int citationEnd;
    if (closeMatch != null &&
        (nextOpenMatch == null || closeMatch.start < nextOpenMatch.start)) {
      // 正常ケース: 対応する閉じカッコがある
      bodyEnd = bodyStart + closeMatch.start;
      citationEnd = bodyStart + closeMatch.end;
    } else {
      // 修復ケース: 閉じカッコが無い。
      // SID引用として意味を成す文字 (s/S/数字/区切り/空白) が続く範囲までを引用とみなす。
      final validBodyChar = RegExp('[sS0-9 \t$_dashChars$_commaChars]');
      var cursor = bodyStart;
      while (cursor < text.length && validBodyChar.hasMatch(text[cursor])) {
        cursor++;
      }
      bodyEnd = cursor;
      citationEnd = cursor;
    }

    final body = text.substring(bodyStart, bodyEnd);
    final sids = _parseSidBody(body);

    // SIDが1つも取れなかった場合は引用ではない(例: 数式や別用途のカッコ)とみなし、
    // このカッコはスキップして次を探す。
    if (sids.isNotEmpty) {
      results.add(SidCitation(
        raw: text.substring(openStart, citationEnd),
        start: openStart,
        end: citationEnd,
        sids: sids,
      ));
    }

    searchStart = citationEnd > openStart ? citationEnd : openStart + 1;
  }

  return results;
}

/// テキストからSID引用記法を取り除いた表示用テキストを返す。
///
/// 引用の前に不自然に残るスペースも同時に整理する。
/// 例: "components ⟦s000011-s000014⟧." → "components."
String stripSidCitations(String text) {
  final citations = parseSidCitations(text);
  if (citations.isEmpty) return text;

  final buffer = StringBuffer();
  var cursor = 0;
  for (final c in citations) {
    var chunk = text.substring(cursor, c.start);
    // 引用直前の余分なスペースを削る (改行は保持する)
    chunk = chunk.replaceFirst(RegExp(r'[ \t]+$'), '');
    buffer.write(chunk);
    cursor = c.end;
  }
  buffer.write(text.substring(cursor));

  return buffer.toString();
}
