import React, { useState, useEffect } from 'react';
import { Hash } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';

export interface CustomColorPickerDialogProps {
  initialColor: string;
  onClose: () => void;
  onSelectColor: (color: string) => void;
}

/**
 * 16進数文字列からHSLへの変換
 */
function hexToHsl(hex: string): { h: number; s: number; l: number } {
  let clean = hex.replace('#', '').trim();
  if (clean.length === 3) {
    clean = clean
      .split('')
      .map((c) => c + c)
      .join('');
  }
  if (clean.length !== 6 && clean.length !== 8) {
    return { h: 42, s: 0.8, l: 0.6 }; // デフォルト Star Gold (#FFB300)
  }
  const r = parseInt(clean.substring(0, 2), 16) / 255;
  const g = parseInt(clean.substring(2, 4), 16) / 255;
  const b = parseInt(clean.substring(4, 6), 16) / 255;

  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  let s = 0;
  const l = (max + min) / 2;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r:
        h = (g - b) / d + (g < b ? 6 : 0);
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      case b:
        h = (r - g) / d + 4;
        break;
    }
    h *= 60;
  }
  return { h, s, l };
}

/**
 * HSLから16進数文字列への変換
 */
function hslToHex(h: number, s: number, l: number): string {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0,
    g = 0,
    b = 0;

  if (h >= 0 && h < 60) {
    r = c;
    g = x;
    b = 0;
  } else if (h >= 60 && h < 120) {
    r = x;
    g = c;
    b = 0;
  } else if (h >= 120 && h < 180) {
    r = 0;
    g = c;
    b = x;
  } else if (h >= 180 && h < 240) {
    r = 0;
    g = x;
    b = c;
  } else if (h >= 240 && h < 300) {
    r = x;
    g = 0;
    b = c;
  } else {
    r = c;
    g = 0;
    b = x;
  }

  const toHex = (val: number) => {
    const hex = Math.round((val + m) * 255).toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  };

  return `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();
}

/**
 * Flutter版 `_CustomColorPickerDialog` と同一のカスタムカラーピッカー。
 * - 彩度 (Saturation) は 0.8 に固定（濁りを防ぎ鮮やかに）
 * - 明度 (Lightness) は 0.4 〜 1.0 にクランプ（暗すぎる色にならないよう制限）
 */
export const CustomColorPickerDialog: React.FC<CustomColorPickerDialogProps> = ({
  initialColor,
  onClose,
  onSelectColor,
}) => {
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const initialHsl = hexToHsl(initialColor);
  const [hue, setHue] = useState(initialHsl.h);
  // Flutter版同様、明度は 0.4 〜 1.0 に制限
  const [lightness, setLightness] = useState(Math.min(Math.max(initialHsl.l, 0.4), 1.0));

  // Saturation は常に 0.8 に固定
  const currentHex = hslToHex(hue, 0.8, lightness);
  const [hexInput, setHexInput] = useState(currentHex);

  // Hue/Lightness変更時にHex入力欄を更新
  useEffect(() => {
    setHexInput(currentHex);
  }, [currentHex]);

  // Hex手入力時の同期
  const handleHexChange = (text: string) => {
    setHexInput(text);
    const clean = text.replace('#', '').trim();
    if (clean.length === 6) {
      const parsedHsl = hexToHsl('#' + clean);
      setHue(parsedHsl.h);
      setLightness(Math.min(Math.max(parsedHsl.l, 0.4), 1.0));
    }
  };

  const titleText = isJa ? 'カスタムカラー' : 'Custom Color';
  const hueLabel = isJa ? '色相 (Hue)' : 'Hue';
  const lightnessLabel = isJa ? '明るさ (Lightness)' : 'Lightness';
  const hexLabel = isJa ? 'カラーコード' : 'Hex Code';
  const cancelText = isJa ? 'キャンセル' : 'Cancel';
  const okText = isJa ? '決定' : 'OK';

  const lightnessGradientLow = hslToHex(hue, 0.8, 0.4);
  const lightnessGradientMid = hslToHex(hue, 0.8, 0.7);

  return (
    <div className="custom-color-dialog-backdrop" onClick={onClose}>
      <div
        className="custom-color-dialog-card"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-labelledby="custom-color-title"
      >
        <div className="custom-color-dialog-header">
          <h3 id="custom-color-title" className="custom-color-dialog-title">
            {titleText}
          </h3>
          <button
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        <div className="custom-color-dialog-body">
          {/* プレビューサークル (80x80px) */}
          <div className="custom-color-preview-wrap">
            <div
              className="custom-color-preview-circle"
              style={{
                backgroundColor: currentHex,
                boxShadow: `0 0 24px 2px ${currentHex}66`,
              }}
            />
          </div>

          {/* 色相 (Hue) スライダー */}
          <div className="custom-color-slider-field">
            <label className="custom-color-slider-label">{hueLabel}</label>
            <div className="custom-color-hue-track-wrap">
              <input
                type="range"
                min="0"
                max="360"
                step="1"
                value={Math.round(hue)}
                onChange={(e) => setHue(parseFloat(e.target.value))}
                className="custom-color-slider custom-color-hue-slider"
                aria-label={hueLabel}
              />
            </div>
          </div>

          {/* 明るさ (Lightness) スライダー: 0.4 〜 1.0 に制限 */}
          <div className="custom-color-slider-field">
            <label className="custom-color-slider-label">{lightnessLabel}</label>
            <div
              className="custom-color-lightness-track-wrap"
              style={{
                background: `linear-gradient(to right, ${lightnessGradientLow}, ${lightnessGradientMid}, #ffffff)`,
              }}
            >
              <input
                type="range"
                min="0.4"
                max="1.0"
                step="0.01"
                value={lightness}
                onChange={(e) => setLightness(parseFloat(e.target.value))}
                className="custom-color-slider custom-color-lightness-slider"
                aria-label={lightnessLabel}
              />
            </div>
          </div>

          {/* カラーコード入力 */}
          <div className="custom-color-hex-field">
            <label className="custom-color-slider-label">{hexLabel}</label>
            <div className="custom-color-hex-input-wrap">
              <Hash size={16} className="custom-color-hex-icon" />
              <input
                type="text"
                value={hexInput}
                onChange={(e) => handleHexChange(e.target.value)}
                placeholder="#FFB300"
                maxLength={7}
                className="custom-color-hex-input"
              />
            </div>
          </div>
        </div>

        {/* ダイアログアクションボタン */}
        <div className="custom-color-dialog-actions">
          <button
            type="button"
            className="course-btn-cancel"
            onClick={onClose}
          >
            {cancelText}
          </button>
          <button
            type="button"
            className="course-btn-submit"
            style={{
              backgroundColor: '#FFB300',
              borderColor: '#FFB300',
              color: '#111422',
            }}
            onClick={() => onSelectColor(currentHex)}
          >
            {okText}
          </button>
        </div>
      </div>
    </div>
  );
};
