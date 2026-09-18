import React, { useState, useEffect } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { Upload, Check, User, Palette, RotateCcw } from 'lucide-react';
import { getProfile, updateProfileFields, uploadAvatar } from '../../lib/profile';
import { notifyProfileUpdate } from '../../hooks/useProfile';
import { supabase } from '../../lib/supabase';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  PRESET_CLAY_AVATARS,
  getGradientsForStyle,
  getTextColorForStyle,
  parsePreset,
  serializePreset,
} from '../../lib/avatar';
import type { UserProfile } from '../../types/profile';

interface ChangeAvatarSheetProps {
  open: boolean;
  onClose: () => void;
  profile: UserProfile | null;
  onUpdated: () => Promise<void>;
}

export const ChangeAvatarSheet: React.FC<ChangeAvatarSheetProps> = ({
  open,
  onClose,
  profile,
  onUpdated,
}) => {
  const { language } = useLanguage();
  const [selectedIcon, setSelectedIcon] = useState<string>('initials');
  const [selectedBgStyle, setSelectedBgStyle] = useState<number>(0);
  const [selectedBgIndex, setSelectedBgIndex] = useState<number>(2);
  const [viewingBgStyle, setViewingBgStyle] = useState<number>(0);
  const [activeTab, setActiveTab] = useState<'icons' | 'backgrounds'>('icons');

  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [socialAvatarUrl, setSocialAvatarUrl] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      const meta = data.user?.user_metadata;
      const url = (meta?.avatar_url || meta?.picture) as string | undefined;
      if (url && typeof url === 'string' && url.trim().length > 0) {
        setSocialAvatarUrl(url.trim());
      }
    });
  }, []);

  useEffect(() => {
    if (!open) return;
    const parsed = parsePreset(profile?.avatar_url || '');
    setSelectedIcon(parsed.icon || 'initials');
    setSelectedBgStyle(parsed.bgStyle ?? 0);
    setSelectedBgIndex(parsed.bgIndex ?? 2);
    setViewingBgStyle(parsed.bgStyle ?? 0);
  }, [profile?.avatar_url, open]);

  const displayName = profile?.username?.trim() || 'Explorer';
  const initials =
    displayName
      .split(' ')
      .filter(Boolean)
      .map((s) => s[0].toUpperCase())
      .slice(0, 2)
      .join('') || 'EX';

  const activeGradients = getGradientsForStyle(selectedBgStyle);
  const currentGradient = activeGradients[selectedBgIndex % activeGradients.length];
  const currentTextColor = getTextColorForStyle(selectedBgStyle, selectedBgIndex);

  const viewingGradients = getGradientsForStyle(viewingBgStyle);

  const isAlreadyUsingSocialAvatar =
    Boolean(socialAvatarUrl && profile?.avatar_url?.trim() === socialAvatarUrl.trim());
  const showRestoreSocial = Boolean(socialAvatarUrl && !isAlreadyUsingSocialAvatar);

  const handleSavePreset = async () => {
    setSaving(true);
    setError(null);
    try {
      const serialized = serializePreset(selectedIcon, selectedBgStyle, selectedBgIndex);
      const updated = await updateProfileFields({ avatar_url: serialized });
      notifyProfileUpdate(updated);
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update avatar');
    } finally {
      setSaving(false);
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setError(null);
    try {
      await uploadAvatar(file);
      const fresh = await getProfile();
      notifyProfileUpdate(fresh);
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to upload photo');
    } finally {
      setUploading(false);
    }
  };

  const handleRestoreSocial = async () => {
    if (!socialAvatarUrl) return;
    setSaving(true);
    setError(null);
    try {
      const updated = await updateProfileFields({ avatar_url: socialAvatarUrl });
      notifyProfileUpdate(updated);
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to restore social avatar');
    } finally {
      setSaving(false);
    }
  };

  const isJa = language === 'ja';

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      title={isJa ? 'アバターを変更' : 'Change Avatar'}
      subtitle={isJa ? 'イニシャル、クレイアバター、背景色、または写真を設定' : 'Choose initials, clay character, background color, or upload a photo'}
    >
      <div className="avatar-sheet-content">
        {error && <p className="auth-error">{error}</p>}

        {/* ── 1. 上部プレビュー (現在選択中のアバター + 背景) ── */}
        <div className="avatar-sheet-preview-wrap">
          <div
            className="avatar-sheet-preview-circle"
            style={{
              background: currentGradient,
              width: 104,
              height: 104,
              boxShadow: '0 10px 30px rgba(0, 0, 0, 0.45)',
            }}
          >
            {selectedIcon === 'initials' ? (
              <span
                style={{
                  fontSize: '2.3rem',
                  fontWeight: 800,
                  color: currentTextColor,
                  userSelect: 'none',
                  letterSpacing: '0.04em',
                }}
              >
                {initials}
              </span>
            ) : (
              <img
                src={`/avatars/${selectedIcon}`}
                alt="Avatar preview"
                className="avatar-sheet-preview-img"
              />
            )}
          </div>
        </div>

        {/* ── 2. カスタム写真のアップロード & ソーシャル画像復元 ── */}
        <div style={{ marginBottom: '1.25rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.5rem' }}>
          <label
            className="btn btn-ghost"
            style={{
              width: '100%',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.5rem',
              padding: '0.65rem 1rem',
              borderRadius: '12px',
              fontSize: '0.88rem',
            }}
          >
            <Upload size={17} />
            <span>{uploading ? (isJa ? 'アップロード中…' : 'Uploading…') : (isJa ? 'フォトライブラリから選択' : 'Choose from Photo Library')}</span>
            <input
              type="file"
              accept="image/*"
              style={{ display: 'none' }}
              onChange={handleFileUpload}
              disabled={uploading || saving}
            />
          </label>

          {showRestoreSocial && (
            <button
              type="button"
              className="btn btn-ghost"
              style={{
                background: 'transparent',
                border: 'none',
                color: 'var(--comet, rgba(255, 255, 255, 0.75))',
                fontSize: '0.82rem',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.4rem',
                padding: '0.35rem 0.75rem',
                cursor: 'pointer',
                borderRadius: '8px',
                transition: 'all 0.15s ease',
              }}
              onClick={handleRestoreSocial}
              disabled={saving || uploading}
            >
              <RotateCcw size={14} />
              <span>{language === 'ja' ? 'ソーシャルアカウントの画像に戻す' : 'Restore Social Account Photo'}</span>
            </button>
          )}
        </div>

        {/* ── 3. タブ選択 (Icons vs Backgrounds) ── */}
        <div className="avatar-tab-bar">
          <button
            type="button"
            className={`avatar-tab-btn ${activeTab === 'icons' ? 'is-active' : ''}`}
            onClick={() => setActiveTab('icons')}
          >
            <User size={16} />
            <span>{isJa ? 'アイコン' : 'Icons'}</span>
          </button>
          <button
            type="button"
            className={`avatar-tab-btn ${activeTab === 'backgrounds' ? 'is-active' : ''}`}
            onClick={() => setActiveTab('backgrounds')}
          >
            <Palette size={16} />
            <span>{isJa ? '背景色' : 'Backgrounds'}</span>
          </button>
        </div>

        {/* ── 4. TAB 1: キャラクター & イニシャル ── */}
        {activeTab === 'icons' && (
          <div>
            <div className="avatar-preset-grid">
              {/* Option 0: イニシャル */}
              <button
                type="button"
                className={`avatar-preset-btn ${selectedIcon === 'initials' ? 'is-selected' : ''}`}
                onClick={() => setSelectedIcon('initials')}
                title="Initials"
              >
                <div
                  style={{
                    width: 48,
                    height: 48,
                    borderRadius: '50%',
                    background: currentGradient,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: currentTextColor,
                    fontWeight: 700,
                    fontSize: '1.15rem',
                    boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
                  }}
                >
                  {initials}
                </div>
                <span
                  style={{
                    marginTop: '0.35rem',
                    fontSize: '0.75rem',
                    color: selectedIcon === 'initials' ? 'var(--star-gold, #fbc02d)' : 'var(--comet)',
                    fontWeight: 600,
                  }}
                >
                  {isJa ? 'イニシャル' : 'Initials'}
                </span>
                {selectedIcon === 'initials' && (
                  <span className="avatar-preset-badge">
                    <Check size={13} strokeWidth={3.5} />
                  </span>
                )}
              </button>

              {/* Options 1..20: クレイアバター */}
              {PRESET_CLAY_AVATARS.map((icon) => {
                const isSelected = selectedIcon === icon;
                return (
                  <button
                    key={icon}
                    type="button"
                    className={`avatar-preset-btn ${isSelected ? 'is-selected' : ''}`}
                    onClick={() => setSelectedIcon(icon)}
                    title={icon.replace('clay_', '').replace('.png', '')}
                  >
                    <img src={`/avatars/${icon}`} alt={icon} className="avatar-preset-btn-img" />
                    {isSelected && (
                      <span className="avatar-preset-badge">
                        <Check size={13} strokeWidth={3.5} />
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* ── 5. TAB 2: 背景カラー (Vivid / Pastel / Dark + 12色) ── */}
        {activeTab === 'backgrounds' && (
          <div>
            {/* サブスタイル選択チップ */}
            <div className="avatar-substyle-bar">
              <button
                type="button"
                className={`avatar-substyle-chip ${viewingBgStyle === 0 ? 'is-active' : ''}`}
                onClick={() => setViewingBgStyle(0)}
              >
                Vivid
              </button>
              <button
                type="button"
                className={`avatar-substyle-chip ${viewingBgStyle === 1 ? 'is-active' : ''}`}
                onClick={() => setViewingBgStyle(1)}
              >
                Pastel
              </button>
              <button
                type="button"
                className={`avatar-substyle-chip ${viewingBgStyle === 2 ? 'is-active' : ''}`}
                onClick={() => setViewingBgStyle(2)}
              >
                Dark
              </button>
            </div>

            {/* 12色グラデーション円 */}
            <div className="avatar-gradient-grid">
              {viewingGradients.map((gradient, idx) => {
                const isSelected = selectedBgStyle === viewingBgStyle && selectedBgIndex === idx;
                return (
                  <button
                    key={idx}
                    type="button"
                    className={`avatar-gradient-circle ${isSelected ? 'is-selected' : ''}`}
                    style={{ background: gradient }}
                    onClick={() => {
                      setSelectedBgStyle(viewingBgStyle);
                      setSelectedBgIndex(idx);
                    }}
                    aria-label={`Color option ${idx + 1}`}
                  >
                    {isSelected && (
                      <div className="avatar-check-badge">
                        <Check size={14} strokeWidth={3.2} color="#ffffff" />
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* ── 6. アクションボタン ── */}
        <div className="avatar-sheet-actions">
          <button
            type="button"
            className="btn btn-primary"
            style={{
              padding: '0.75rem 1rem',
              borderRadius: '12px',
              fontSize: '0.95rem',
              fontWeight: 700,
            }}
            onClick={handleSavePreset}
            disabled={saving || uploading}
          >
            {saving ? (isJa ? '保存中…' : 'Saving…') : (isJa ? 'アバターに設定' : 'Set as Avatar')}
          </button>
        </div>
      </div>
    </AdaptiveSheet>
  );
};
