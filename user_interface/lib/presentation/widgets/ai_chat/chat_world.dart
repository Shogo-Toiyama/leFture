// lib/presentation/widgets/ai_chat/chat_world.dart
import 'package:flutter/material.dart';

/// AIチャットのシートが今どちらの世界にいるか。アプリの設定ではなく、シートを
/// 開いた画面で決まる(Homeなど宇宙の画面はuniverse、Deep Notesなど紙の画面はpaper。
/// webappの紙のパネル `.is-paper` と同じ考え方)。
enum ChatWorld { universe, paper }

/// 考え中の動きなどで使う、世界ごとの色。同じ名前の色を、宇宙では光る明るい色、
/// 紙ではインクに馴染む濃いめの色にしてある(docs/chatbot_motion_reference.html の PALETTES)。
class ChatMotionPalette {
  const ChatMotionPalette._(this.colors);

  final List<Color> colors;

  static const universe = ChatMotionPalette._([
    Color(0xFFFFB300), // gold
    Color(0xFF42A5F5), // blue
    Color(0xFFB39DDB), // lilac
    Color(0xFF80DEEA), // mint
    Color(0xFFF48FB1), // rose
  ]);

  static const paper = ChatMotionPalette._([
    Color(0xFFCC8D00),
    Color(0xFF1E70C4),
    Color(0xFF7656B2),
    Color(0xFF008996),
    Color(0xFFC44E74),
  ]);

  static ChatMotionPalette of(ChatWorld world) =>
      world == ChatWorld.paper ? paper : universe;
}

/// 紙の世界の地の色とインクの色(AppColors.paperと同じ値)。描画の計算で使う。
const chatPaperColor = Color(0xFFFAF5E9);
const chatInkColor = Color(0xFF3E3228);
