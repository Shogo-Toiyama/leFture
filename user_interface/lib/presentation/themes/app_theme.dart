import 'package:flutter/material.dart';

class AppTheme {
  // 色の定義
  static const Color _primary = Color(0xFFFFB300); // ゴールド系
  static const Color _primaryDark = Color(0xFFCC8D00);
  static const Color _accent = Color(0xFFFFD54F);  // 柔らかい黄色
  static const Color _background = Color(0xFFFAF5E9); // ほんのりクリーム
  static const Color _surface = Colors.white;
  static const Color _textMain = Color(0xFF333333);

  /// アプリ全体の Light テーマ
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: _primary,
        onPrimary: Colors.white,
        secondary: _accent,
        onSecondary: _textMain,
        error: Colors.red.shade700,
        onError: Colors.white,
        surface: _surface,
        onSurface: _textMain,
      ),
      scaffoldBackgroundColor: _background,
    );

    return base.copyWith(
      // フォント周り
      textTheme: _buildTextTheme(base.textTheme),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(
          color: _textMain,
        ),
      ),

      // カード
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 2,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ボタン系
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // しっかり丸く
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: const BorderSide(color: _primary),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryDark,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // TextField など
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
        labelStyle: TextStyle(
          color: Colors.grey.shade700,
        ),
      ),

      // BottomNavigationBar (純正を使う場合)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: _primary,
        unselectedItemColor: Colors.grey.shade500,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),

      // ダイアログなど
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: _textMain,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: _textMain,
          height: 1.4,
        ),
      ),
    );
  }

  /// 明朝寄りの雰囲気を出したいテキストテーマ
  /// 本当に明朝体にしたい場合は、後でフォントファイルを追加して
  /// fontFamily を差し替える感じ
  static TextTheme _buildTextTheme(TextTheme base) {
    const displayFont = 'serifDisplay'; // 後で好きなフォント名に差し替え
    const bodyFont = 'serifBody';

    return base
        .copyWith(
          displayLarge: base.displayLarge?.copyWith(
            fontFamily: displayFont,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          displayMedium: base.displayMedium?.copyWith(
            fontFamily: displayFont,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontFamily: displayFont,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontFamily: displayFont,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontFamily: bodyFont,
            height: 1.4,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontFamily: bodyFont,
            height: 1.4,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontFamily: bodyFont,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(
          bodyColor: _textMain,
          displayColor: _textMain,
        );
  }
}
