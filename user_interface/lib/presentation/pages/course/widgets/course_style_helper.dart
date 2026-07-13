import 'package:flutter/material.dart';

/// コースのカラーコードとアイコンの文字列マッピングを提供するヘルパークラス。
class CourseStyleHelper {
  CourseStyleHelper._();

  /// プリセットのカラーパレット（ダークテーマに映えるカラフルな色合い）
  static const List<Color> presetColors = [
    Color(0xFFFFB300), // Star Gold (Primary)
    Color(0xFFEF5350), // Red
    Color(0xFFF06292), // Pink
    Color(0xFFBA68C8), // Purple
    Color(0xFF7986CB), // Indigo
    Color(0xFF64B5F6), // Blue
    Color(0xFF4DB6AC), // Teal
    Color(0xFF81C784), // Green
    Color(0xFFFF9800), // Orange
  ];

  /// Colorを16進数文字列（#RRGGBB）に変換する
  static String colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  /// 16進数文字列（#RRGGBB または #AARRGGBB）をColorに変換する
  static Color hexToColor(String? hex, {Color fallback = const Color(0xFFFFB300)}) {
    if (hex == null || hex.isEmpty) return fallback;
    final cleanHex = hex.replaceFirst('#', '');
    try {
      if (cleanHex.length == 6) {
        return Color(int.parse('FF$cleanHex', radix: 16));
      } else if (cleanHex.length == 8) {
        return Color(int.parse(cleanHex, radix: 16));
      }
    } catch (_) {
      // パース失敗時はフォールバック
    }
    return fallback;
  }

  /// アイコン名（文字列）からIconDataへのマッピング
  static const Map<String, IconData> iconMap = {
    // 学校・勉強 (General Study)
    'school': Icons.school_outlined,
    'book': Icons.book_outlined,
    'menu_book': Icons.menu_book_outlined,
    'auto_stories': Icons.auto_stories_outlined,
    'quiz': Icons.quiz_outlined,
    'edit_note': Icons.edit_note_outlined,
    'workspace_premium': Icons.workspace_premium_outlined,

    // 文学・言語学 (Literature & Linguistics)
    'history_edu': Icons.history_edu_outlined,
    'translate': Icons.translate_outlined,
    'abc': Icons.abc_outlined,
    'chat_bubble': Icons.chat_bubble_outline,
    'record_voice_over': Icons.record_voice_over_outlined,

    // 歴史・哲学・文化 (History, Phil, Culture)
    'museum': Icons.museum_outlined,
    'hourglass_empty': Icons.hourglass_empty_outlined,
    'self_improvement': Icons.self_improvement_outlined,
    'lightbulb': Icons.lightbulb_outline,
    'psychology': Icons.psychology_outlined,
    'festival': Icons.festival_outlined,
    'theater_comedy': Icons.theater_comedy_outlined,

    // 政治・法・国際 (Politics, Law, Global)
    'gavel': Icons.gavel_outlined,
    'balance': Icons.balance_outlined,
    'account_balance': Icons.account_balance_outlined,
    'how_to_vote': Icons.how_to_vote_outlined,
    'public': Icons.public_outlined,
    'flag': Icons.flag_outlined,

    // 数学・物理・化学・天文 (STEM)
    'functions': Icons.functions_outlined,
    'calculate': Icons.calculate_outlined,
    'timeline': Icons.timeline_outlined,
    'science': Icons.science_outlined,
    'biotech': Icons.biotech_outlined,
    'nights_stay': Icons.nights_stay_outlined,
    'rocket_launch': Icons.rocket_launch_outlined,
    'wb_sunny': Icons.wb_sunny_outlined,
    'bolt': Icons.bolt,

    // 機械・電子電気・情報・建築 (Engineering, IT, Architecture)
    'settings': Icons.settings_outlined,
    'construction': Icons.construction_outlined,
    'memory': Icons.memory_outlined,
    'terminal': Icons.terminal_outlined,
    'code': Icons.code_outlined,
    'architecture': Icons.architecture_outlined,
    'domain': Icons.domain_outlined,

    // 農学・水産 (Agriculture & Fisheries)
    'agriculture': Icons.agriculture_outlined,
    'grass': Icons.grass_outlined,
    'nature': Icons.nature_outlined,
    'sailing': Icons.sailing_outlined,
    'set_meal': Icons.set_meal_outlined,
    'phishing': Icons.phishing_outlined,

    // 医学・薬学・看護・歯科医 (Medical)
    'medical_services': Icons.medical_services_outlined,
    'local_hospital': Icons.local_hospital_outlined,
    'vaccines': Icons.vaccines_outlined,
    'medication': Icons.medication_outlined,
    'health_and_safety': Icons.health_and_safety_outlined,
    'monitor_heart': Icons.monitor_heart_outlined,
    'sentiment_satisfied': Icons.sentiment_satisfied_alt_outlined,

    // スポーツ・健康 (Sports & Health)
    'sports_soccer': Icons.sports_soccer_outlined,
    'sports_basketball': Icons.sports_basketball_outlined,
    'fitness_center': Icons.fitness_center_outlined,
    'directions_run': Icons.directions_run_outlined,
    'spa': Icons.spa_outlined,
    'apple': Icons.apple_outlined,

    // 美術・フィルム・観光 (Art, Film, Tourism)
    'palette': Icons.palette_outlined,
    'brush': Icons.brush_outlined,
    'movie': Icons.movie_outlined,
    'theaters': Icons.theaters_outlined,
    'flight_takeoff': Icons.flight_takeoff_outlined,
    'luggage': Icons.luggage_outlined,
    'attractions': Icons.attractions_outlined,
  };

  /// 文字列からIconDataを取得。見つからない場合は `Icons.school_outlined` を返す。
  static IconData getIcon(String? name) {
    if (name == null) return Icons.school_outlined;
    return iconMap[name] ?? Icons.school_outlined;
  }
}

/// UIでのカテゴリ分類用の定義
class CourseIconCategory {
  final String title;
  final String emoji;
  final List<String> iconNames;

  const CourseIconCategory({
    required this.title,
    required this.emoji,
    required this.iconNames,
  });
}

/// コース編集シート用のカテゴリ一覧
const List<CourseIconCategory> courseIconCategories = [
  CourseIconCategory(
    title: 'School',
    emoji: '🎓',
    iconNames: ['school', 'book', 'menu_book', 'auto_stories', 'quiz', 'edit_note', 'workspace_premium'],
  ),
  CourseIconCategory(
    title: 'Humanity & Lang',
    emoji: '✍️',
    iconNames: ['history_edu', 'translate', 'abc', 'chat_bubble', 'record_voice_over', 'museum', 'hourglass_empty', 'self_improvement', 'lightbulb', 'psychology', 'festival', 'theater_comedy'],
  ),
  CourseIconCategory(
    title: 'Society & Law',
    emoji: '⚖️',
    iconNames: ['gavel', 'balance', 'account_balance', 'how_to_vote', 'public', 'flag'],
  ),
  CourseIconCategory(
    title: 'Science & Space',
    emoji: '🔬',
    iconNames: ['functions', 'calculate', 'timeline', 'science', 'biotech', 'nights_stay', 'rocket_launch', 'wb_sunny', 'bolt'],
  ),
  CourseIconCategory(
    title: 'Tech & Build',
    emoji: '💻',
    iconNames: ['settings', 'construction', 'memory', 'terminal', 'code', 'architecture', 'domain'],
  ),
  CourseIconCategory(
    title: 'Agri & Marine',
    emoji: '🌾',
    iconNames: ['agriculture', 'grass', 'nature', 'sailing', 'set_meal', 'phishing'],
  ),
  CourseIconCategory(
    title: 'Medical',
    emoji: '🏥',
    iconNames: ['medical_services', 'local_hospital', 'vaccines', 'medication', 'health_and_safety', 'monitor_heart', 'sentiment_satisfied'],
  ),
  CourseIconCategory(
    title: 'Sports & Health',
    emoji: '⚽',
    iconNames: ['sports_soccer', 'sports_basketball', 'fitness_center', 'directions_run', 'spa', 'apple'],
  ),
  CourseIconCategory(
    title: 'Art & Travel',
    emoji: '🎨',
    iconNames: ['palette', 'brush', 'movie', 'theaters', 'flight_takeoff', 'luggage', 'attractions'],
  ),
];
