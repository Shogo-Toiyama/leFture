// lib/presentation/pages/onboarding/widgets/onboarding_illustrations.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Languageステップ用の青グラデーションベクターイラスト。
/// 地球儀・言語の対話バブル・オーディオ波形がコズミックな軌道で調和するデザイン。
const _languageIllustrationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 92" fill="none">
  <defs>
    <!-- メインの鮮やかな青グラデーション -->
    <linearGradient id="langBlueGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#60A5FA"/>
      <stop offset="50%" stop-color="#3B82F6"/>
      <stop offset="100%" stop-color="#1D4ED8"/>
    </linearGradient>

    <!-- シアン〜スカイブルーのハイライトグラデーション -->
    <linearGradient id="langCyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#7DD3FC"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>

    <!-- 淡いソフトグロー -->
    <radialGradient id="langGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#38BDF8" stop-opacity="0.32"/>
      <stop offset="60%" stop-color="#1E40AF" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#1E3A8A" stop-opacity="0"/>
    </radialGradient>

    <!-- 半透明ガラスカードグラデーション -->
    <linearGradient id="langGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#60A5FA" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="#1E3A8A" stop-opacity="0.06"/>
    </linearGradient>
  </defs>

  <!-- 背景のアンビエントグロー -->
  <ellipse cx="110" cy="46" rx="72" ry="36" fill="url(#langGlow)"/>

  <!-- 軌道リング (Orbit) -->
  <ellipse cx="110" cy="46" rx="84" ry="24" transform="rotate(-12 110 46)" stroke="url(#langCyanGrad)" stroke-width="1.2" stroke-dasharray="3 3" opacity="0.45"/>
  <ellipse cx="110" cy="46" rx="98" ry="30" transform="rotate(-12 110 46)" stroke="url(#langBlueGrad)" stroke-width="0.8" opacity="0.25"/>

  <!-- 軌道上のサテライトドット -->
  <circle cx="28" cy="44" r="2" fill="#93C5FD" opacity="0.8"/>
  <circle cx="190" cy="48" r="2.5" fill="#38BDF8"/>
  <circle cx="68" cy="22" r="1.5" fill="#BFDBFE"/>
  <circle cx="158" cy="68" r="1.8" fill="#60A5FA"/>

  <!-- 中央のグローブ (地球儀) -->
  <circle cx="110" cy="46" r="24" fill="#0B1528" stroke="url(#langBlueGrad)" stroke-width="1.8"/>
  <circle cx="110" cy="46" r="24" fill="url(#langGlass)"/>
  <!-- 経線・緯線 -->
  <ellipse cx="110" cy="46" rx="13" ry="24" stroke="#60A5FA" stroke-width="1.2" opacity="0.6"/>
  <line x1="110" y1="22" x2="110" y2="70" stroke="#60A5FA" stroke-width="1.2" opacity="0.6"/>
  <line x1="86" y1="46" x2="134" y2="46" stroke="#60A5FA" stroke-width="1.2" opacity="0.6"/>
  <path d="M89 36 Q110 41 131 36" stroke="#93C5FD" stroke-width="1" opacity="0.45" fill="none"/>
  <path d="M89 56 Q110 51 131 56" stroke="#93C5FD" stroke-width="1" opacity="0.45" fill="none"/>

  <!-- 左側: 言語シンボル吹き出し (A / 言語) -->
  <g transform="translate(42, 28)">
    <rect width="36" height="28" rx="8" fill="#0E1E38" stroke="url(#langCyanGrad)" stroke-width="1.4"/>
    <rect width="36" height="28" rx="8" fill="url(#langGlass)"/>
    <!-- 吹き出しのしっぽ -->
    <path d="M26 28 L32 34 L31 28 Z" fill="#0E1E38" stroke="url(#langCyanGrad)" stroke-width="1.4" stroke-linejoin="round"/>
    <!-- 吹き出し内の文字 "A" -->
    <text x="18" y="19" text-anchor="middle" fill="#93C5FD" font-size="13" font-family="system-ui, -apple-system, sans-serif" font-weight="700">A</text>
  </g>

  <!-- 右側: 音声・波形吹き出し (録音言語) -->
  <g transform="translate(142, 34)">
    <rect width="36" height="28" rx="8" fill="#0E1E38" stroke="url(#langBlueGrad)" stroke-width="1.4"/>
    <rect width="36" height="28" rx="8" fill="url(#langGlass)"/>
    <!-- 吹き出しのしっぽ -->
    <path d="M10 28 L4 34 L5 28 Z" fill="#0E1E38" stroke="url(#langBlueGrad)" stroke-width="1.4" stroke-linejoin="round"/>
    <!-- 音波バー -->
    <line x1="11" y1="14" x2="11" y2="20" stroke="#38BDF8" stroke-width="2" stroke-linecap="round"/>
    <line x1="15" y1="11" x2="15" y2="23" stroke="#60A5FA" stroke-width="2" stroke-linecap="round"/>
    <line x1="19" y1="8" x2="19" y2="26" stroke="#93C5FD" stroke-width="2" stroke-linecap="round"/>
    <line x1="23" y1="12" x2="23" y2="22" stroke="#60A5FA" stroke-width="2" stroke-linecap="round"/>
    <line x1="27" y1="15" x2="27" y2="19" stroke="#38BDF8" stroke-width="2" stroke-linecap="round"/>
  </g>

  <!-- キラリと光る星 (スパークル) -->
  <g transform="translate(162, 16)">
    <path d="M0 5 Q5 5 5 0 Q5 5 10 5 Q5 5 5 10 Q5 5 0 5 Z" fill="#BAE6FD" opacity="0.9"/>
  </g>
  <g transform="translate(54, 62)">
    <path d="M0 4 Q4 4 4 0 Q4 4 8 4 Q4 4 4 8 Q4 4 0 4 Z" fill="#93C5FD" opacity="0.75"/>
  </g>
</svg>
''';

/// Permissionsステップ用のオレンジグラデーションベクターイラスト。
/// マイク・セキュリティシールド・音声パルス・通知ベルが安心感を与えるデザイン。
const _permissionsIllustrationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 92" fill="none">
  <defs>
    <!-- メインの鮮やかなオレンジグラデーション -->
    <linearGradient id="permOrangeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBBF24"/>
      <stop offset="50%" stop-color="#F59E0B"/>
      <stop offset="100%" stop-color="#EA580C"/>
    </linearGradient>

    <!-- コーラル〜ウォームアンバーのグラデーション -->
    <linearGradient id="permAmberGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FDE68A"/>
      <stop offset="100%" stop-color="#F97316"/>
    </linearGradient>

    <!-- 淡いオレンジグロー -->
    <radialGradient id="permGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#F59E0B" stop-opacity="0.32"/>
      <stop offset="60%" stop-color="#C2410C" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#7C2D12" stop-opacity="0"/>
    </radialGradient>

    <!-- 半透明ガラスカードグラデーション -->
    <linearGradient id="permGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBBF24" stop-opacity="0.20"/>
      <stop offset="100%" stop-color="#9A3412" stop-opacity="0.05"/>
    </linearGradient>
  </defs>

  <!-- 背景のアンビエントグロー -->
  <ellipse cx="110" cy="46" rx="72" ry="36" fill="url(#permGlow)"/>

  <!-- 軌道パルスライン (Pulse Orbit) -->
  <ellipse cx="110" cy="46" rx="84" ry="24" transform="rotate(-10 110 46)" stroke="url(#permAmberGrad)" stroke-width="1.2" stroke-dasharray="3 3" opacity="0.45"/>
  <ellipse cx="110" cy="46" rx="98" ry="30" transform="rotate(-10 110 46)" stroke="url(#permOrangeGrad)" stroke-width="0.8" opacity="0.25"/>

  <!-- 軌道上のパーティクル -->
  <circle cx="28" cy="48" r="2" fill="#FDE68A" opacity="0.8"/>
  <circle cx="192" cy="44" r="2.5" fill="#F59E0B"/>
  <circle cx="70" cy="70" r="1.5" fill="#FED7AA"/>
  <circle cx="160" cy="22" r="1.8" fill="#F97316"/>

  <!-- 中央背後のセキュリティシールド (安心・保護) -->
  <path d="M110 18 L134 26 C134 46 122 59 110 66 C98 59 86 46 86 26 Z" fill="#1C1408" stroke="url(#permOrangeGrad)" stroke-width="1.8"/>
  <path d="M110 20 L132 27 C132 45 121 57 110 64 C99 57 88 45 88 27 Z" fill="url(#permGlass)"/>

  <!-- 中央のマイクアイコン (Microphone) -->
  <g transform="translate(98, 26)">
    <!-- マイク本体 -->
    <rect x="7" y="4" width="10" height="18" rx="5" fill="url(#permAmberGrad)"/>
    <!-- 集音スタンド・受話部 -->
    <path d="M3 13 C3 20 21 20 21 13" stroke="#FDE68A" stroke-width="1.8" stroke-linecap="round" fill="none"/>
    <line x1="12" y1="21" x2="12" y2="27" stroke="#FDE68A" stroke-width="1.8" stroke-linecap="round"/>
    <line x1="7" y1="27" x2="17" y2="27" stroke="#FDE68A" stroke-width="1.8" stroke-linecap="round"/>
  </g>

  <!-- 左側: 音波パルスバッジ (Live Recording) -->
  <g transform="translate(42, 30)">
    <circle cx="16" cy="16" r="15" fill="#1C1408" stroke="url(#permAmberGrad)" stroke-width="1.4"/>
    <circle cx="16" cy="16" r="15" fill="url(#permGlass)"/>
    <!-- 音波円弧 -->
    <path d="M12 11 A7 7 0 0 0 12 21" stroke="#FDE68A" stroke-width="1.5" stroke-linecap="round" fill="none"/>
    <path d="M9 7 A13 13 0 0 0 9 25" stroke="#F59E0B" stroke-width="1.5" stroke-linecap="round" fill="none" opacity="0.6"/>
    <!-- 中心ドット -->
    <circle cx="16" cy="16" r="2.5" fill="#FDE68A"/>
  </g>

  <!-- 右側: 通知ベル ＆ チェックバッジ (Notification & Verified) -->
  <g transform="translate(144, 28)">
    <circle cx="18" cy="18" r="16" fill="#1C1408" stroke="url(#permOrangeGrad)" stroke-width="1.4"/>
    <circle cx="18" cy="18" r="16" fill="url(#permGlass)"/>
    <!-- ベルアイコン -->
    <path d="M18 10 C15.5 10 13.5 12 13.5 14.5 L13.5 19 L11.5 21 L24.5 21 L22.5 19 L22.5 14.5 C22.5 12 20.5 10 18 10 Z" fill="#FDE68A"/>
    <circle cx="18" cy="23" r="1.5" fill="#F59E0B"/>
    <!-- 小さなチェックマークバッジ -->
    <circle cx="27" cy="10" r="5.5" fill="#10B981" stroke="#1C1408" stroke-width="1.2"/>
    <path d="M25 10 L26.5 11.5 L29.5 8.5" stroke="#FFFFFF" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  </g>

  <!-- キラリと光る星 (スパークル) -->
  <g transform="translate(166, 14)">
    <path d="M0 5 Q5 5 5 0 Q5 5 10 5 Q5 5 5 10 Q5 5 0 5 Z" fill="#FEF08A" opacity="0.9"/>
  </g>
  <g transform="translate(52, 60)">
    <path d="M0 4 Q4 4 4 0 Q4 4 8 4 Q4 4 4 8 Q4 4 0 4 Z" fill="#FDBA74" opacity="0.8"/>
  </g>
</svg>
''';

/// 言語設定ステップ（Language Step）用イラストWidget
class LanguageStepIllustration extends StatelessWidget {
  const LanguageStepIllustration({super.key, this.height = 84});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SvgPicture.string(
        _languageIllustrationSvg,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// パーミッション設定ステップ（Permissions Step）用イラストWidget
class PermissionsStepIllustration extends StatelessWidget {
  const PermissionsStepIllustration({super.key, this.height = 84});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SvgPicture.string(
        _permissionsIllustrationSvg,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// プロフィール設定ステップ（Profile Step）用の緑グラデーションベクターイラスト。
/// アバターバッジ・学習ノート・目標の星が調和するデザイン。
const _profileIllustrationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 92" fill="none">
  <defs>
    <!-- メインのエメラルド〜グリーングラデーション -->
    <linearGradient id="profGreenGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#34D399"/>
      <stop offset="50%" stop-color="#10B981"/>
      <stop offset="100%" stop-color="#047857"/>
    </linearGradient>

    <!-- ミント〜ライムグリーンのハイライトグラデーション -->
    <linearGradient id="profMintGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#A7F3D0"/>
      <stop offset="100%" stop-color="#059669"/>
    </linearGradient>

    <!-- 淡いグリーングロー -->
    <radialGradient id="profGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#10B981" stop-opacity="0.32"/>
      <stop offset="60%" stop-color="#065F46" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#064E3B" stop-opacity="0"/>
    </radialGradient>

    <!-- 半透明ガラスカードグラデーション -->
    <linearGradient id="profGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#34D399" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="#064E3B" stop-opacity="0.06"/>
    </linearGradient>
  </defs>

  <!-- 背景のアンビエントグロー -->
  <ellipse cx="110" cy="46" rx="72" ry="36" fill="url(#profGlow)"/>

  <!-- 軌道リング (Orbit) -->
  <ellipse cx="110" cy="46" rx="84" ry="24" transform="rotate(-11 110 46)" stroke="url(#profMintGrad)" stroke-width="1.2" stroke-dasharray="3 3" opacity="0.45"/>
  <ellipse cx="110" cy="46" rx="98" ry="30" transform="rotate(-11 110 46)" stroke="url(#profGreenGrad)" stroke-width="0.8" opacity="0.25"/>

  <!-- 軌道上のパーティクル -->
  <circle cx="28" cy="46" r="2" fill="#A7F3D0" opacity="0.8"/>
  <circle cx="192" cy="46" r="2.5" fill="#34D399"/>
  <circle cx="70" cy="22" r="1.5" fill="#D1FAE5"/>
  <circle cx="158" cy="70" r="1.8" fill="#10B981"/>

  <!-- 中央のユーザーアバターバッジ (Profile) -->
  <circle cx="110" cy="46" r="24" fill="#081C15" stroke="url(#profGreenGrad)" stroke-width="1.8"/>
  <circle cx="110" cy="46" r="24" fill="url(#profGlass)"/>
  <!-- アバターの頭部 -->
  <circle cx="110" cy="38" r="8" fill="url(#profMintGrad)"/>
  <!-- アバターの肩・体 -->
  <path d="M96 58 C96 50 102 48 110 48 C118 48 124 50 124 58" fill="url(#profGreenGrad)"/>

  <!-- 左側: 学習ノート・本 (Bio / Studies) -->
  <g transform="translate(42, 28)">
    <rect width="36" height="28" rx="8" fill="#081C15" stroke="url(#profMintGrad)" stroke-width="1.4"/>
    <rect width="36" height="28" rx="8" fill="url(#profGlass)"/>
    <!-- 開いたノートアイコン -->
    <path d="M10 11 C13 10 16 11 18 12 C20 11 23 10 26 11 L26 23 C23 22 20 23 18 24 C16 23 13 22 10 23 Z" fill="none" stroke="#A7F3D0" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    <line x1="18" y1="12" x2="18" y2="24" stroke="#A7F3D0" stroke-width="1.5"/>
  </g>

  <!-- 右側: 目標・成長のコンパス / スパークル (Future Goals / Dreams) -->
  <g transform="translate(142, 34)">
    <rect width="36" height="28" rx="8" fill="#081C15" stroke="url(#profGreenGrad)" stroke-width="1.4"/>
    <rect width="36" height="28" rx="8" fill="url(#profGlass)"/>
    <!-- 羅針盤・ひらめき星 -->
    <path d="M18 7 L21 14 L28 14 L22 18 L24 25 L18 21 L12 25 L14 18 L8 14 L15 14 Z" fill="url(#profMintGrad)"/>
  </g>

  <!-- キラリと光る星 (スパークル) -->
  <g transform="translate(164, 15)">
    <path d="M0 5 Q5 5 5 0 Q5 5 10 5 Q5 5 5 10 Q5 5 0 5 Z" fill="#D1FAE5" opacity="0.9"/>
  </g>
  <g transform="translate(52, 62)">
    <path d="M0 4 Q4 4 4 0 Q4 4 8 4 Q4 4 4 8 Q4 4 0 4 Z" fill="#6EE7B7" opacity="0.8"/>
  </g>
</svg>
''';

/// プロフィール設定ステップ（Profile Step）用イラストWidget
class ProfileStepIllustration extends StatelessWidget {
  const ProfileStepIllustration({super.key, this.height = 84});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SvgPicture.string(
        _profileIllustrationSvg,
        fit: BoxFit.contain,
      ),
    );
  }
}

