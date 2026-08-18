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

  /// メインタイトル（上の文字）を返します。
  /// [kAutoDetectLanguageCode] ('auto') の場合、表示言語に応じて「自動判定」や「Auto-detect」を返します。
  String getNativeName(String displayLanguageCode) {
    if (code == kAutoDetectLanguageCode) {
      if (displayLanguageCode == 'ja') {
        return '自動判定';
      }
      return 'Auto-detect';
    }
    return nativeName;
  }

  /// 現在の表示言語 [displayLanguageCode] ('ja', 'en' など) に応じたサブテキスト（下の文字）を返します。
  /// 'auto' の場合は全体の見た目・高さを揃えるため、複数言語録音用の説明文を返します。
  String? localizedName(String displayLanguageCode) {
    if (code == kAutoDetectLanguageCode) {
      if (displayLanguageCode == 'ja') {
        return '複数言語が混ざる講義を録音する場合に選択';
      }
      return 'Use when multiple languages are spoken in class';
    }

    if (displayLanguageCode == 'ja') {
      switch (code) {
        case 'en':
          return '英語';
        case 'ja':
          return '日本語';
        case 'fr':
          return 'フランス語';
        case 'es':
          return 'スペイン語';
        case 'de':
          return 'ドイツ語';
        case 'zh':
          return '中国語';
        case 'yue':
          return '広東語';
        case 'ko':
          return '韓国語';
        case 'pt':
          return 'ポルトガル語';
        case 'it':
          return 'イタリア語';
        case 'ru':
          return 'ロシア語';
        case 'ar':
          return 'アラビア語';
        case 'hi':
          return 'ヒンディー語';
        default:
          return englishName;
      }
    }
    return englishName;
  }

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

/// 録音言語の「自動判定」を表す予約コード。選択すると、サーバー側
/// (Cloudflare/Modal Whisper)にもオンデバイスWhisperにも特定の言語を
/// 強制せず、Whisper自身の言語判定に任せる。lectures.recording_languageは
/// このコードではなくnullとして保存される(バックエンド側は元々「未設定
/// ならWhisperの自動判定に任せる」という規約で統一されているため)。
const String kAutoDetectLanguageCode = 'auto';

/// 録音・文字起こしに対応している言語一覧
const List<AppLanguage> kRecordingLanguages = [
  AppLanguage(
    code: kAutoDetectLanguageCode,
    nativeName: 'Auto-detect',
    englishName: 'Auto-detect',
  ),
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
