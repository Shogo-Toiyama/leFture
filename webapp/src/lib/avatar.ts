export const PRESET_CLAY_AVATARS = [
  'clay_bear.webp',
  'clay_books.webp',
  'clay_boy.webp',
  'clay_burger.webp',
  'clay_camera.webp',
  'clay_cat.webp',
  'clay_coffee.webp',
  'clay_dog.webp',
  'clay_earth.webp',
  'clay_galaxy.webp',
  'clay_gamepad.webp',
  'clay_girl.webp',
  'clay_headphones.webp',
  'clay_owl.webp',
  'clay_palette.webp',
  'clay_penguin.webp',
  'clay_robot.webp',
  'clay_rocket.webp',
  'clay_suitcase.webp',
  'clay_unicorn.webp',
] as const;

/// 1. ビビッド (12色)
export const VIVID_GRADIENTS = [
  'linear-gradient(135deg, #FF2D55, #FF3B30)', // 1. 赤
  'linear-gradient(135deg, #FF3B30, #FF9500)', // 2. 赤橙
  'linear-gradient(135deg, #FF9500, #FFCC00)', // 3. 橙黄
  'linear-gradient(135deg, #FFCC00, #A3E635)', // 4. 黄ライム
  'linear-gradient(135deg, #84CC16, #34C759)', // 5. ライムグリーン
  'linear-gradient(135deg, #34C759, #10B981)', // 6. フレッシュグリーン
  'linear-gradient(135deg, #10B981, #059669)', // 7. ディープエメラルド
  'linear-gradient(135deg, #00C7BE, #30B0C7)', // 8. ティール
  'linear-gradient(135deg, #30B0C7, #007AFF)', // 9. シアンブルー
  'linear-gradient(135deg, #007AFF, #5856D6)', // 10. ブルーインディゴ
  'linear-gradient(135deg, #5856D6, #AF52DE)', // 11. インディゴパープル
  'linear-gradient(135deg, #AF52DE, #FF2D55)', // 12. パープルマゼンタ
];

/// 2. パステル (12色)
export const PASTEL_GRADIENTS = [
  'linear-gradient(135deg, #FFC3D0, #FFF0F5)', // 1
  'linear-gradient(135deg, #FFB7C5, #FFE4E1)', // 2
  'linear-gradient(135deg, #FFE4E1, #FFD8B1)', // 3
  'linear-gradient(135deg, #FFD8B1, #FFE5B4)', // 4
  'linear-gradient(135deg, #FFF59D, #FFFDE7)', // 5
  'linear-gradient(135deg, #D9F99D, #ECFDF5)', // 6
  'linear-gradient(135deg, #A7F3D0, #E0F2F1)', // 7
  'linear-gradient(135deg, #E0F2F1, #BAE6FD)', // 8
  'linear-gradient(135deg, #BAE6FD, #E1F5FE)', // 9
  'linear-gradient(135deg, #C7D2FE, #F0F4FF)', // 10
  'linear-gradient(135deg, #DDD6FE, #F5F3FF)', // 11
  'linear-gradient(135deg, #FDF2F8, #FCE7F3)', // 12
];

/// パステル各背景に対応する文字色 (12色)
export const PASTEL_TEXT_COLORS = [
  '#E11D48',
  '#E11D48',
  '#EA580C',
  '#D97706',
  '#CA8A04',
  '#65A30D',
  '#059669',
  '#0891B2',
  '#2563EB',
  '#4F46E5',
  '#334155',
  '#DB2777',
];

/// 3. ダーク (12色)
export const DARK_GRADIENTS = [
  'linear-gradient(135deg, #450A0A, #881337)', // 1
  'linear-gradient(135deg, #881337, #991B1B)', // 2
  'linear-gradient(135deg, #7C2D12, #9A3412)', // 3
  'linear-gradient(135deg, #451A03, #78350F)', // 4
  'linear-gradient(135deg, #3F6212, #65A30D)', // 5
  'linear-gradient(135deg, #022C22, #064E3B)', // 6
  'linear-gradient(135deg, #064E3B, #047857)', // 7
  'linear-gradient(135deg, #0F4C81, #1E3E62)', // 8
  'linear-gradient(135deg, #0B192C, #1E293B)', // 9
  'linear-gradient(135deg, #1E1B4B, #312E81)', // 10
  'linear-gradient(135deg, #2E1065, #581C87)', // 11
  'linear-gradient(135deg, #05070A, #141722)', // 12
];

export function getGradientsForStyle(bgStyle: number): string[] {
  if (bgStyle === 1) return PASTEL_GRADIENTS;
  if (bgStyle === 2) return DARK_GRADIENTS;
  return VIVID_GRADIENTS;
}

export function getTextColorForStyle(bgStyle: number, bgIndex: number): string {
  if (bgStyle === 1) {
    return PASTEL_TEXT_COLORS[bgIndex % PASTEL_TEXT_COLORS.length];
  }
  return '#ffffff';
}

export interface ParsedAvatarPreset {
  icon: string; // 'initials' or 'clay_bear.webp'
  bgStyle: number; // 0=vivid, 1=pastel, 2=dark
  bgIndex: number; // 0..11
}

export function parsePreset(presetStr: string): ParsedAvatarPreset {
  const payload = presetStr.replace(/^preset:/, '');
  const parts = payload.split(';');
  let icon = 'initials';
  let bgStyle = 0;
  let bgIndex = 2;

  for (const part of parts) {
    const [k, v] = part.split('=');
    if (!k || !v) continue;
    const key = k.trim();
    const val = v.trim();
    if (key === 'icon') icon = val.replace(/\.png$/, '.webp');
    if (key === 'bg_style') bgStyle = parseInt(val, 10) || 0;
    if (key === 'bg_index') bgIndex = parseInt(val, 10) || 0;
  }
  return { icon, bgStyle, bgIndex };
}

export function serializePreset(icon: string, bgStyle: number, bgIndex: number): string {
  return `preset:icon=${icon};bg_style=${bgStyle};bg_index=${bgIndex}`;
}
