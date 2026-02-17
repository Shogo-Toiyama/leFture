import 'package:flutter/material.dart';

class AppColors {
  // インスタンス化禁止
  AppColors._();

  // ===========================================================================
  // 🌟 Brand Identity (ブランドの核となる色)
  // ===========================================================================
  
  /// 【金星の輝き】
  /// アプリのプライマリーカラー。成長、達成、価値を表すゴールド。
  /// ボタンや強調したいアイコンに使用。
  static const starGold = Color(0xFFFFB300);

  /// 【深淵のゴールド】
  /// starGoldの影色。ボタンのプレス時や、少し落ち着いた強調に。
  static const deepGold = Color(0xFFCC8D00);

  /// 【若葉の緑】
  /// 成功、完了、成長を表す色。Goal Treeの葉などに。
  static const growthGreen = Color(0xFF4CAF50);

  /// 【警告の琥珀】
  /// 注意喚起や、まだ完了していないタスクに。
  static const alertAmber = Color(0xFFFFA000);

  /// 【添削の赤】
  /// エラーや削除、先生の赤ペンのような色。
  static const correctionRed = Color(0xFFE53935);


  // ===========================================================================
  // 📜 Paper World (ノート・読み物パート)
  // 「目に優しく、紙の質感をデジタルで再現する」
  // ===========================================================================
  static const paper = _PaperColors();

  // ===========================================================================
  // 🌌 Universe World (ダッシュボード・銀河パート)
  // 「無限の奥行きと、ガラスのような透明感」
  // ===========================================================================
  static const universe = _UniverseColors();
}

/// 📜 ノート（ライトテーマ）用パレット
class _PaperColors {
  const _PaperColors();

  /// 【クリーム・ヴェラム】
  /// 真っ白(#FFFFFF)ではなく、高級な羊皮紙のような温かみのあるクリーム色。
  /// 目の疲れを軽減し、長時間読んでも疲れない背景色。
  final background = const Color(0xFFFAF5E9);

  /// 【純白のカード】
  /// クリーム色の背景の上に置く、カードやダイアログの色。
  /// 背景より少し明るくすることで、浮き上がって見える。
  final surface = const Color(0xFFFFFFFF);

  /// 【エスプレッソ・インク】
  /// 真っ黒(#000000)ではなく、深みのある焦げ茶色。
  /// クリーム色の紙に一番馴染み、コントラストが高すぎず読みやすい文字色。
  final textInk = const Color(0xFF3E3228);

  /// 【古びた鉛筆】
  /// サブテキスト、日付、補足情報用のグレー。
  /// 少し温かみを含ませたグレー。
  final textPencil = const Color(0xFF8D8D8D);

  /// 【薄墨のライン】
  /// 区切り線や枠線に使う、主張しない薄い色。
  final line = const Color(0xFFE0E0E0);
}

/// 🌌 宇宙（ダークテーマ）用パレット
class _UniverseColors {
  const _UniverseColors();

  /// 【虚空 (Void)】
  /// 銀河の背景。完全な黒(#000000)ではなく、ほんの少し青みを含んだリッチブラック。
  /// OLEDディスプレイで美しく沈み込む色。
  // final voidBackground = const Color(0xFF0B0D12);
  // final voidBackground = const Color(0xFF0F172A);
  final voidBackground = const Color(0xFF111422);
  // final voidBackground = const Color(0xFF13111A);

  /// 【星屑 (Stardust)】
  /// ダーク背景上の文字色。完全な白ではなく、少しだけ透過感を感じさせる白。
  final textStarlight = const Color(0xFFF2F2F2);

  /// 【彗星の尾 (Comet)】
  /// ダーク背景上のサブテキスト。青みがかったグレー。
  final textComet = const Color(0xFF8E99A6);

  /// 【宇宙船の窓 (Glass)】
  /// グラスモーフィズム用。背景をぼかして使う半透明の白。
  /// 透過度 10%
  final glassWhiteLow = const Color(0x1AFFFFFF); 

  /// 【宇宙船の窓・強 (Glass High)】
  /// グラスモーフィズム用。強調したいカードなど。
  /// 透過度 20%
  final glassWhiteHigh = const Color(0x33FFFFFF);

  /// 【境界の光 (Edge)】
  /// グラスモーフィズムの枠線（Border）に使う、鋭い光のような白。
  /// 透過度 30%
  final glassBorder = const Color(0x4DFFFFFF);
}