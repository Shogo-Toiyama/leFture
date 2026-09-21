import React, { useState } from 'react';
import type { Announcement, AnnouncementType } from '../../types/content';
import { updateAnnouncement } from '../../lib/content';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

export interface AnnouncementEditModalProps {
  announcement: Announcement;
  onClose: () => void;
  onAnnouncementUpdated?: (updated: Announcement) => void;
}

interface TypeOption {
  type: AnnouncementType;
  labelKey: 'announcementTypeTodo' | 'announcementTypeEvent' | 'announcementTypeInfo' | 'announcementTypeHint';
  icon: string;
  color: string;
}

const TYPE_OPTIONS: TypeOption[] = [
  { type: 'TODO', labelKey: 'announcementTypeTodo', icon: 'task_alt', color: '#4ade80' },
  { type: 'EVENT', labelKey: 'announcementTypeEvent', icon: 'event', color: '#60a5fa' },
  { type: 'INFO', labelKey: 'announcementTypeInfo', icon: 'info', color: '#d8b4fe' },
  { type: 'HINT', labelKey: 'announcementTypeHint', icon: 'lightbulb', color: '#fbbf24' },
];

export const AnnouncementEditModal: React.FC<AnnouncementEditModalProps> = ({
  announcement,
  onClose,
  onAnnouncementUpdated,
}) => {
  const { t } = useLanguage();
  const [selectedType, setSelectedType] = useState<AnnouncementType>(
    (announcement.type?.toUpperCase() as AnnouncementType) || 'TODO'
  );
  const [title, setTitle] = useState(announcement.title?.trim() ?? '');
  const [description, setDescription] = useState(announcement.description?.trim() ?? '');
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanTitle = title.trim();
    if (!cleanTitle) {
      setErrorMsg(t('announcementEditTitleRequired'));
      return;
    }

    setSaving(true);
    setErrorMsg(null);

    try {
      const cleanDesc = description.trim() ? description.trim() : null;
      const updated = await updateAnnouncement(announcement.id, {
        title: cleanTitle,
        description: cleanDesc,
        type: selectedType,
      });

      onAnnouncementUpdated?.(updated);
      onClose();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <ModalDialog title={t('announcementEditTitle')} onClose={onClose} maxWidth={520}>
      <form onSubmit={handleSubmit} className="lecture-edit-form announcement-edit-form">
        {errorMsg && (
          <div className="app-error-box" style={{ marginBottom: '1rem' }}>
            <span>{errorMsg}</span>
          </div>
        )}

        {/* 1. Type Selector */}
        <div className="edit-form-field">
          <label className="edit-form-label">{t('announcementEditType')}</label>
          <div className="announcement-type-selector-wrap" role="radiogroup" aria-label={t('announcementEditType')}>
            {TYPE_OPTIONS.map((opt) => {
              const isSelected = selectedType === opt.type;
              return (
                <button
                  key={opt.type}
                  type="button"
                  className={`announcement-type-chip ${isSelected ? 'is-selected' : ''}`}
                  style={{
                    borderColor: isSelected ? opt.color : undefined,
                    backgroundColor: isSelected ? `${opt.color}24` : undefined,
                    color: isSelected ? opt.color : undefined,
                  }}
                  onClick={() => setSelectedType(opt.type)}
                  role="radio"
                  aria-checked={isSelected}
                >
                  <span className="material-symbols-outlined chip-icon" style={{ fontSize: '1.05rem' }}>
                    {opt.icon}
                  </span>
                  <span>{t(opt.labelKey)}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* 2. Title Field */}
        <div className="edit-form-field">
          <label className="edit-form-label">{t('announcementEditTitleLabel')}</label>
          <input
            type="text"
            className="auth-input edit-title-input"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={t('announcementEditTitleHint')}
            required
            autoFocus
          />
        </div>

        {/* 3. Description Field */}
        <div className="edit-form-field">
          <label className="edit-form-label">{t('announcementEditDescriptionLabel')}</label>
          <textarea
            className="auth-input edit-title-input announcement-desc-textarea"
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder={t('announcementEditDescriptionHint')}
          />
        </div>

        {/* Actions */}
        <div className="edit-form-actions" style={{ marginTop: '0.5rem' }}>
          <button
            type="button"
            className="keyword-btn-cancel"
            onClick={onClose}
            disabled={saving}
          >
            {t('cancel')}
          </button>
          <button
            type="submit"
            className="auth-submit-btn edit-btn-submit"
            disabled={saving}
          >
            {saving ? t('saving') : t('save')}
          </button>
        </div>
      </form>
    </ModalDialog>
  );
};
