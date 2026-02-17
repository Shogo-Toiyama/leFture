import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  /// アプリ唯一の固定テーマ
  static ThemeData get main {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: ColorScheme.dark(
        primary: AppColors.starGold,
        surface: AppColors.universe.voidBackground,
        onSurface: AppColors.universe.textStarlight,
        error: AppColors.correctionRed,
      ),

      scaffoldBackgroundColor: AppColors.universe.voidBackground,

      textTheme: TextTheme(
        bodyMedium: TextStyle(color: AppColors.universe.textStarlight),
        bodyLarge: TextStyle(color: AppColors.universe.textStarlight),
      ).apply(
        bodyColor: AppColors.universe.textStarlight, 
        displayColor: AppColors.universe.textStarlight,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
    );
  }

  static ThemeData get reader {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light, // ★ここはライト！

      colorScheme: ColorScheme.light(
        primary: AppColors.starGold,
        surface: AppColors.paper.surface,
        onSurface: AppColors.paper.textInk,
        error: AppColors.correctionRed,
      ),

      scaffoldBackgroundColor: AppColors.paper.background,

      textTheme: TextTheme(
        bodyMedium: TextStyle(color: AppColors.paper.textInk),
        bodyLarge: TextStyle(color: AppColors.paper.textInk),
      ).apply(
        bodyColor: AppColors.paper.textInk, 
        displayColor: AppColors.paper.textInk,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.paper.textInk),
      ),
    );
  }
}