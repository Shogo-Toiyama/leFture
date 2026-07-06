import 'sid_citation.dart';

/// Markdown入りテキストを、1〜数行のプレビュー表示用のプレーンテキストに変換する。
///
/// カルーセルカードやリストのサブタイトルなど、MarkdownBodyを使えない
/// (maxLines/ellipsisが必要な) 場所で使う。SID引用も同時に除去する。
String plainTextPreview(String source) {
  var text = stripSidCitations(source);

  // 見出し記号 (# ## ###)
  text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  // 太字/斜体 (**text** __text__ *text* _text_)
  text = text.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'(?<!\w)\*(?!\s)(.+?)(?<!\s)\*(?!\w)'), (m) => m.group(1)!);
  // インラインコード
  text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);
  // リンク [text](url)
  text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);
  // 箇条書き記号
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  // 引用記号
  text = text.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

  // 連続する空白・改行をまとめる
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  return text;
}
