// lib/presentation/widgets/ai_chat/chat_colors.dart
import 'package:flutter/material.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIチャットの会話の色。webappの index.css の `.chat-*`(宇宙)と `.is-paper .chat-*`(紙)と同じ値。
/// シートが開いた画面の世界([ChatWorld])ごとに1組ずつ持つ。
class ChatColors {
  const ChatColors({
    required this.sheet,
    required this.text,
    required this.strongText,
    required this.link,
    required this.codeBackground,
    required this.codeText,
    required this.preBackground,
    required this.preBorder,
    required this.blockquoteBorder,
    required this.blockquoteText,
    required this.tableBorder,
    required this.rule,
    required this.bubbleBackground,
    required this.bubbleBorder,
    required this.bubbleText,
    required this.quoteBackground,
    required this.quoteBorder,
    required this.quoteText,
    required this.stageText,
    required this.actionForeground,
    required this.actionForegroundStrong,
    required this.actionHover,
    required this.actionDone,
    required this.menuBackground,
    required this.menuBorder,
    required this.accent,
    required this.citeBackground,
    required this.citeText,
    required this.noticeBackground,
    required this.noticeBorder,
    required this.noticeText,
    required this.danger,
    required this.care,
    required this.inputBackground,
    required this.inputBorder,
    required this.hintText,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipText,
    required this.mentionFull,
    required this.mentionRef,
  });

  final Color sheet;

  // 回答(Markdown)
  final Color text;
  final Color strongText;
  final Color link;
  final Color codeBackground;
  final Color codeText;
  final Color preBackground;
  final Color preBorder;
  final Color blockquoteBorder;
  final Color blockquoteText;
  final Color tableBorder;
  final Color rule;

  // 自分の吹き出し
  final Color bubbleBackground;
  final Color bubbleBorder;
  final Color bubbleText;
  final Color quoteBackground;
  final Color quoteBorder;
  final Color quoteText;

  // 段階の表示・操作の行・メニュー
  final Color stageText;
  final Color actionForeground;
  final Color actionForegroundStrong;
  final Color actionHover;
  final Color actionDone;
  final Color menuBackground;
  final Color menuBorder;

  /// 強調の色(宇宙では金、紙では濃い琥珀)。「もっと見る」・編集中の枠・リンクなどに使う。
  final Color accent;

  // 出典の印
  final Color citeBackground;
  final Color citeText;

  // 知らせの帯・エラー・危機対応の枠
  final Color noticeBackground;
  final Color noticeBorder;
  final Color noticeText;
  final Color danger;
  final Color care;

  // 入力欄
  final Color inputBackground;
  final Color inputBorder;
  final Color hintText;

  // 入力欄の上の資料のチップ・「@名前」の色(全文で添付 / メンション)
  final Color chipBackground;
  final Color chipBorder;
  final Color chipText;
  final Color mentionFull;
  final Color mentionRef;

  static const _gold = Color(0xFFFFB300);

  static const universe = ChatColors(
    sheet: Color(0xFF121628),
    text: Color(0xFFE8EAEE),
    strongText: Colors.white,
    link: _gold,
    codeBackground: Color(0x14FFFFFF),
    codeText: Color(0xFFE8EAEE),
    preBackground: Color(0xFF0D101C),
    preBorder: Color(0x2EFFFFFF),
    blockquoteBorder: Color(0x2EFFFFFF),
    blockquoteText: Color(0xFF8E99A6),
    tableBorder: Color(0x2EFFFFFF),
    rule: Color(0x1FFFFFFF),
    bubbleBackground: Color(0xFF262C47),
    bubbleBorder: Color(0x14FFFFFF),
    bubbleText: Color(0xFFE8EAEE),
    quoteBackground: Color(0x0DFFFFFF),
    quoteBorder: _gold,
    quoteText: Color(0xFFCFD4DC),
    stageText: Color(0xFF8E99A6),
    actionForeground: Color(0xFF8E99A6),
    actionForegroundStrong: Color(0xFFE8EAEE),
    actionHover: Color(0x17FFFFFF),
    actionDone: Color(0xFF66BB6A),
    menuBackground: Color(0xFF171B2B),
    menuBorder: Color(0x1FFFFFFF),
    accent: _gold,
    citeBackground: Color(0x29FFB300),
    citeText: _gold,
    noticeBackground: Color(0x14FFB300),
    noticeBorder: Color(0x59FFB300),
    noticeText: Color(0xFFE8EAEE),
    danger: Color(0xFFFF8A80),
    care: Color(0xFF42A5F5),
    inputBackground: Color(0x12FFFFFF),
    inputBorder: Color(0x1FFFFFFF),
    hintText: Color(0xFF5F6878),
    chipBackground: Color(0x0DFFFFFF),
    chipBorder: Color(0x1FFFFFFF),
    chipText: Color(0xFFCFD4DC),
    mentionFull: Color(0x3DFFB300),
    mentionRef: Color(0x3D78AAFF),
  );

  static const paper = ChatColors(
    sheet: Color(0xFFFAF5E9),
    text: Color(0xFF2E231A),
    strongText: Color(0xFF1A140F),
    link: Color(0xFFB45309),
    codeBackground: Color(0x143E3228),
    codeText: Color(0xFF3B2C22),
    preBackground: Color(0xFFF4EDE0),
    preBorder: Color(0xFFE4DCCE),
    blockquoteBorder: Color(0xFFD6CCBD),
    blockquoteText: Color(0xFF6B5C50),
    tableBorder: Color(0xFFE4DCCE),
    rule: Color(0x243E3228),
    bubbleBackground: Color(0xFFECE3D2),
    bubbleBorder: Color(0xFFDFD4C0),
    bubbleText: Color(0xFF2B2118),
    quoteBackground: Color(0xA6FFFFFF),
    quoteBorder: Color(0xFFD97706),
    quoteText: Color(0xFF5C4B3E),
    stageText: Color(0xFF8C7A6B),
    actionForeground: Color(0xFF8C7A6B),
    actionForegroundStrong: Color(0xFF3E3228),
    actionHover: Color(0x143E3228),
    actionDone: Color(0xFF2F7D4A),
    menuBackground: Colors.white,
    menuBorder: Color(0xFFDFD5C2),
    accent: Color(0xFFB45309),
    citeBackground: Color(0x26D97706),
    citeText: Color(0xFFB45309),
    noticeBackground: Color(0x14B45309),
    noticeBorder: Color(0x66B45309),
    noticeText: Color(0xFF3E3228),
    danger: Color(0xFFB3261E),
    care: Color(0xFF1E70C4),
    inputBackground: Colors.white,
    inputBorder: Color(0x243E3228),
    hintText: Color(0xFFA39A90),
    chipBackground: Color(0xFFF5EEDF),
    chipBorder: Color(0xFFDFD4C0),
    chipText: Color(0xFF4A3B30),
    mentionFull: Color(0x33D97706),
    mentionRef: Color(0x242563EB),
  );

  static ChatColors of(ChatWorld world) =>
      world == ChatWorld.paper ? paper : universe;
}
