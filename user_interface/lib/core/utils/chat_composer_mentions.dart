// lib/core/utils/chat_composer_mentions.dart
import 'package:lefture/domain/entities/chat.dart';

/// 入力欄の中の「@名前」の文字列処理。webappの webapp/src/lib/chatMentions.ts の入力側を移したもの
/// (保存された本文の印を見せる側は chat_mentions.dart)。
///
/// 入力欄はふつうの文字のまま(日本語の変換と相性が良い)で、資料は「@名前」の文字として入れる。
/// 送るときに「@名前」を印 ⟦att:資料のid⟧ に置き換える。

/// 入力欄に入れる名前の長さの上限(長い題名は省く)。
const _labelMaxChars = 40;

/// 「@名前」が指す資料。
sealed class MentionTarget {
  const MentionTarget();
}

/// この会話にすでにある資料。modeは全文で添付 / メンション。
class ExistingMention extends MentionTarget {
  const ExistingMention({required this.attachmentId, required this.mode});

  final String attachmentId;
  final ChatAttachmentMode mode;

  ExistingMention withMode(ChatAttachmentMode next) =>
      ExistingMention(attachmentId: attachmentId, mode: next);
}

/// この送信で新しく添付する資料(テキストの下書き・アップロード中のファイル)。
class DraftMention extends MentionTarget {
  const DraftMention(this.localId);

  final String localId;
}

class ComposerMention {
  const ComposerMention({required this.label, required this.target});

  /// 入力欄の中の文字("@" から始まる)
  final String label;
  final MentionTarget target;

  ComposerMention withTarget(MentionTarget next) =>
      ComposerMention(label: label, target: next);
}

/// 入力欄に入れる「@名前」。同じ名前が既にあれば (2) などを付けて区別する。
String makeMentionLabel(String title, Iterable<String> taken) {
  final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  final name = clean.isEmpty ? 'material' : clean;
  final runes = name.runes.toList();
  final shortened = runes.length > _labelMaxChars
      ? '${String.fromCharCodes(runes.take(_labelMaxChars - 1))}…'
      : name;
  final base = '@$shortened';
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  for (var n = 2; ; n++) {
    final next = '$base ($n)';
    if (!used.contains(next)) return next;
  }
}

/// カーソルの直前が「@入力中の言葉」なら、その開始位置と言葉(@の後ろ)を返す(資料の候補を出す)。
/// @は行頭か空白の直後のときだけ(メールアドレスなどでは出さない)。既に入れた「@名前」の中では出さない。
({int start, String query})? findMentionQuery(
  String value,
  int caret,
  List<String> labels,
) {
  if (caret < 0 || caret > value.length) return null;
  final before = value.substring(0, caret);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  final query = before.substring(at + 1);
  if (query.length > 30 || RegExp(r'\s').hasMatch(query)) return null;
  if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
  if (labels.any((label) => value.startsWith(label, at))) return null;
  return (start: at, query: query);
}

/// 入力欄の文字の中で、名前がある範囲(色を付けるため)。重ならないように長い名前を優先する。
List<({int start, int end, ComposerMention mention})> mentionRanges(
  String value,
  List<ComposerMention> mentions,
) {
  final ranges = <({int start, int end, ComposerMention mention})>[];
  final taken = List<bool>.filled(value.length, false);
  final byLength = [...mentions]
    ..sort((a, b) => b.label.length.compareTo(a.label.length));
  for (final mention in byLength) {
    var from = 0;
    for (;;) {
      final i = value.indexOf(mention.label, from);
      if (i < 0) break;
      final end = i + mention.label.length;
      var free = true;
      for (var k = i; k < end; k++) {
        if (taken[k]) {
          free = false;
          break;
        }
      }
      if (free) {
        ranges.add((start: i, end: end, mention: mention));
        for (var k = i; k < end; k++) {
          taken[k] = true;
        }
      }
      from = end;
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

/// 送る本文: 「@名前」を印に置き換える。[tokenIdFor]がnullを返すもの(まだ準備中など)は名前のまま残す。
String toMessageContent(
  String value,
  List<ComposerMention> mentions,
  String? Function(ComposerMention mention) tokenIdFor,
) {
  final out = StringBuffer();
  var pos = 0;
  for (final r in mentionRanges(value, mentions)) {
    final id = tokenIdFor(r.mention);
    out
      ..write(value.substring(pos, r.start))
      ..write(id == null ? value.substring(r.start, r.end) : chatMentionToken(id));
    pos = r.end;
  }
  out.write(value.substring(pos));
  return out.toString();
}

/// 入力欄に残っている(送るときに使う)メンション。
List<ComposerMention> presentMentions(
  String value,
  List<ComposerMention> mentions,
) {
  final present = {for (final r in mentionRanges(value, mentions)) r.mention};
  return [
    for (final m in mentions)
      if (present.contains(m)) m,
  ];
}

/// 入力欄で指している既存の資料(同じ資料を何度指しても1つ。全文で添付が1つでもあれば全文)。
List<ChatAttachmentRef> existingReferences(List<ComposerMention> used) {
  final refs = <String, ChatAttachmentMode>{};
  for (final m in used) {
    final t = m.target;
    if (t is! ExistingMention) continue;
    refs[t.attachmentId] =
        refs[t.attachmentId] == ChatAttachmentMode.full ||
            t.mode == ChatAttachmentMode.full
        ? ChatAttachmentMode.full
        : ChatAttachmentMode.mention;
  }
  return [
    for (final e in refs.entries)
      ChatAttachmentRef(attachmentId: e.key, mode: e.value),
  ];
}

/// 削除で「@名前」の途中が欠けたとき、その名前を丸ごと消した後の入力を返す(欠けていなければnull)。
///
/// 途中が欠けると、どの資料か分からなくなるため、webappのBackspaceと同じく1回で丸ごと消す。
/// [oldValue]→[newValue]が1か所の削除(文字を足していない)で、その削除が名前に触れていれば、
/// 名前の全体を消す。戻り値はカーソルの位置つき。
({String text, int caret})? removeBrokenMention(
  String oldValue,
  String newValue,
  List<ComposerMention> mentions,
) {
  if (newValue.length >= oldValue.length) return null;
  // 共通の先頭・末尾から、消えた範囲を求める
  var prefix = 0;
  while (prefix < newValue.length &&
      prefix < oldValue.length &&
      newValue.codeUnitAt(prefix) == oldValue.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < newValue.length - prefix &&
      suffix < oldValue.length - prefix &&
      newValue.codeUnitAt(newValue.length - 1 - suffix) ==
          oldValue.codeUnitAt(oldValue.length - 1 - suffix)) {
    suffix++;
  }
  final delStart = prefix;
  final delEnd = oldValue.length - suffix;
  if (delEnd <= delStart) return null;
  // 消えたのが、名前を丸ごと含むだけなら、そのまま(欠けてはいない)
  for (final r in mentionRanges(oldValue, mentions)) {
    final touches = delStart < r.end && delEnd > r.start;
    if (!touches) continue;
    final whole = delStart <= r.start && delEnd >= r.end;
    if (whole) continue;
    // 名前の途中が欠けた: 名前の全体を消す(消えた範囲とつなげる)
    final from = delStart < r.start ? delStart : r.start;
    final to = delEnd > r.end ? delEnd : r.end;
    final text = oldValue.substring(0, from) + oldValue.substring(to);
    return (text: text, caret: from);
  }
  return null;
}
