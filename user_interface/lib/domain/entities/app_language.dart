/// アプリ内で使用する言語の定義。
/// [code] は BCP-47 言語コード（例: 'en', 'ja'）。
/// [nativeName] はその言語自身の文字で表記した名前（例: 日本語）。
/// [englishName] は英語での名称（例: Japanese）。
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
  });

  final String code;
  final String nativeName;
  final String englishName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AppLanguage && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

/// アプリ画面表示に対応している言語一覧（モック: 将来的に拡張する）
const List<AppLanguage> kDisplayLanguages = [
  AppLanguage(code: 'en', nativeName: 'English', englishName: 'English'),
  AppLanguage(code: 'ja', nativeName: '日本語', englishName: 'Japanese'),
];

/// 録音・文字起こしに対応している言語一覧
const List<AppLanguage> kRecordingLanguages = [
  AppLanguage(code: 'en', nativeName: 'English', englishName: 'English'),
  AppLanguage(code: 'ja', nativeName: '日本語', englishName: 'Japanese'),
  AppLanguage(code: 'fr', nativeName: 'Français', englishName: 'French'),
  AppLanguage(code: 'es', nativeName: 'Español', englishName: 'Spanish'),
  AppLanguage(code: 'de', nativeName: 'Deutsch', englishName: 'German'),
  AppLanguage(code: 'zh', nativeName: '中文', englishName: 'Chinese'),
  AppLanguage(code: 'yue', nativeName: '廣東話', englishName: 'Cantonese'),
  AppLanguage(code: 'ko', nativeName: '한국어', englishName: 'Korean'),
  AppLanguage(code: 'pt', nativeName: 'Português', englishName: 'Portuguese'),
  AppLanguage(code: 'it', nativeName: 'Italiano', englishName: 'Italian'),
  AppLanguage(code: 'ru', nativeName: 'Русский', englishName: 'Russian'),
  AppLanguage(code: 'ar', nativeName: 'العربية', englishName: 'Arabic'),
  AppLanguage(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi'),
];

/// 言語コードから [kRecordingLanguages] の中で一致する言語を返す。
/// 見つからなければ 'en' を返す。
AppLanguage recordingLanguageFromCode(String code) {
  return kRecordingLanguages.firstWhere(
    (l) => l.code == code,
    orElse: () => kRecordingLanguages.first,
  );
}

/// 言語コードから [kDisplayLanguages] の中で一致する言語を返す。
/// 見つからなければ 'en' を返す。
AppLanguage displayLanguageFromCode(String code) {
  return kDisplayLanguages.firstWhere(
    (l) => l.code == code,
    orElse: () => kDisplayLanguages.first,
  );
}
