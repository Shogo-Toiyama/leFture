import 'package:markdown/markdown.dart' as md;

// CommonMarkの強調記号の開閉判定("flanking rule")は、直前が句読点で直後に
// 空白/句読点が続かない場合は閉じ記号として認識しない、というルールになっている。
// 英語のような単語間に必ずスペースが入る言語では問題にならないが、日本語のように
// 全角括弧などの直後にスペース無しで文が続くと、意図した`**強調**`が閉じられずに
// 記号がそのまま残ってしまう(例: 「**ビューポート（Viewport）**にマッピング」の
// 閉じ`**`は、直前の`）`が句読点・直後の`に`が非空白/非句読点のため無効判定される)。
// アプリが表示するMarkdownは常にこちらが生成/制御しているAI由来のテキストであり、
// 任意のユーザー入力ではないため、flankingルールを無視して`**...**`を無条件に
// 太字として扱う簡易シンタックスに置き換える。
class CjkSafeBoldSyntax extends md.InlineSyntax {
  CjkSafeBoldSyntax() : super(r'\*\*(.+?)\*\*');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final innerNodes = md.InlineParser(match[1]!, parser.document).parse();
    parser.addNode(md.Element('strong', innerNodes));
    return true;
  }
}

final List<md.InlineSyntax> cjkSafeInlineSyntaxes = [CjkSafeBoldSyntax()];
