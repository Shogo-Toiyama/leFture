// lib/l10n/tutorial/tutorial_content.dart
import 'package:lefture/l10n/tutorial/tutorial_content_en.dart';
import 'package:lefture/l10n/tutorial/tutorial_content_ja.dart';
import 'package:lefture/l10n/tutorial/tutorial_content_model.dart';

export 'tutorial_content_en.dart';
export 'tutorial_content_ja.dart';
export 'tutorial_content_model.dart';

/// 言語コードに応じたチュートリアルコンテンツを取得する関数。
/// 新しい言語を追加した際は、ここに対応する言語のデータを登録する。
TutorialContent getTutorialContent(String languageCode) {
  switch (languageCode) {
    case 'ja':
      return kTutorialContentJa;
    case 'en':
    default:
      return kTutorialContentEn;
  }
}
