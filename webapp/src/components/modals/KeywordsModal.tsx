import React, { useState } from 'react';
import type { Keyword, LectureTopic } from '../../types/content';
import { updateKeyword } from '../../lib/content';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

export interface KeywordsModalProps {
  keywords: Keyword[];
  topics: LectureTopic[];
  onClose: () => void;
  onKeywordUpdated?: (updated: Keyword) => void;
}

export const KeywordsModal: React.FC<KeywordsModalProps> = ({
  keywords,
  topics,
  onClose,
  onKeywordUpdated,
}) => {
  const { language } = useLanguage();
  const title = language === 'ja' ? 'キーワード' : 'Keywords';
  const emptyText = language === 'ja' ? 'まだ何もありません' : 'Nothing here yet';

  // State for inline editing
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editWord, setEditWord] = useState('');
  const [editDef, setEditDef] = useState('');
  const [saving, setSaving] = useState(false);

  // Group keywords by topic_number
  const topicMap = new Map<number, LectureTopic>();
  topics.forEach((t) => topicMap.set(t.index, t));

  const grouped = new Map<number, Keyword[]>();
  keywords.forEach((k) => {
    const list = grouped.get(k.topic_number) || [];
    list.push(k);
    grouped.set(k.topic_number, list);
  });

  const sortedTopicNumbers = Array.from(
    new Set([...topics.map((t) => t.index), ...Array.from(grouped.keys())])
  ).sort((a, b) => a - b);

  const handleStartEdit = (k: Keyword) => {
    setEditingId(k.id);
    setEditWord(k.keyword || '');
    setEditDef(k.definition || '');
  };

  const handleCancelEdit = () => {
    setEditingId(null);
    setEditWord('');
    setEditDef('');
  };

  const handleSaveEdit = async (k: Keyword) => {
    setSaving(true);
    try {
      await updateKeyword(k.id, {
        keyword: editWord.trim(),
        definition: editDef.trim(),
      });
      const updated: Keyword = {
        ...k,
        keyword: editWord.trim(),
        definition: editDef.trim(),
      };
      onKeywordUpdated?.(updated);
      setEditingId(null);
    } catch (err) {
      console.error('Failed to save keyword:', err);
    } finally {
      setSaving(false);
    }
  };

  const handleToggleSave = async (k: Keyword) => {
    const currentSaved = Boolean(k.metadata && (k.metadata as { saved?: boolean }).saved === true);
    const nextSaved = !currentSaved;
    try {
      await updateKeyword(k.id, {
        isSaved: nextSaved,
        existingMetadata: k.metadata,
      });
      const updated: Keyword = {
        ...k,
        metadata: {
          ...(k.metadata ?? {}),
          saved: nextSaved,
        },
      };
      onKeywordUpdated?.(updated);
    } catch (err) {
      console.error('Failed to toggle keyword bookmark:', err);
    }
  };

  return (
    <ModalDialog title={title} count={keywords.length} onClose={onClose} maxWidth={680}>
      {keywords.length === 0 ? (
        <div className="modal-empty-state">
          <p>{emptyText}</p>
        </div>
      ) : (
        <div className="keywords-grouped-flow">
          {sortedTopicNumbers.map((topicNum) => {
            const kwList = grouped.get(topicNum);
            if (!kwList || kwList.length === 0) return null;

            const topic = topicMap.get(topicNum);
            const topicTitle = topic?.topic_title || `Topic ${topicNum}`;

            return (
              <div key={topicNum} className="keyword-topic-section">
                {/* Topic Section Header */}
                <div className="keyword-section-header">
                  <span className="keyword-section-badge">Topic {topicNum}</span>
                  <span className="keyword-section-title">{topicTitle}</span>
                </div>

                {/* Keyword Cards */}
                <div className="keyword-cards-stack">
                  {kwList.map((k) => {
                    const isEditing = editingId === k.id;
                    const isSaved = Boolean(k.metadata && (k.metadata as { saved?: boolean }).saved === true);

                    if (isEditing) {
                      return (
                        <div key={k.id} className="keyword-card-editing">
                          <input
                            type="text"
                            className="auth-input keyword-edit-input"
                            value={editWord}
                            onChange={(e) => setEditWord(e.target.value)}
                            placeholder={language === 'ja' ? '単語・用語' : 'Keyword'}
                            autoFocus
                          />
                          <textarea
                            className="auth-input keyword-edit-textarea"
                            value={editDef}
                            onChange={(e) => setEditDef(e.target.value)}
                            placeholder={language === 'ja' ? '説明・定義' : 'Definition'}
                            rows={3}
                          />
                          <div className="keyword-edit-actions">
                            <button
                              type="button"
                              className="keyword-btn-cancel"
                              onClick={handleCancelEdit}
                              disabled={saving}
                            >
                              {language === 'ja' ? 'キャンセル' : 'Cancel'}
                            </button>
                            <button
                              type="button"
                              className="auth-submit-btn keyword-btn-save"
                              onClick={() => handleSaveEdit(k)}
                              disabled={saving || !editWord.trim()}
                            >
                              {saving
                                ? (language === 'ja' ? '保存中…' : 'Saving…')
                                : (language === 'ja' ? '保存' : 'Save')}
                            </button>
                          </div>
                        </div>
                      );
                    }

                    return (
                      <div key={k.id} className="keyword-item-card">
                        <div className="keyword-item-main-row">
                          <h4 className="keyword-item-word">{k.keyword || 'Untitled Term'}</h4>
                          <div className="keyword-item-actions">
                            <button
                              type="button"
                              className="keyword-icon-btn"
                              onClick={() => handleStartEdit(k)}
                              aria-label="Edit keyword"
                            >
                              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="keyword-action-svg">
                                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                              </svg>
                            </button>

                            <button
                              type="button"
                              className={`keyword-icon-btn ${isSaved ? 'is-saved' : ''}`}
                              onClick={() => handleToggleSave(k)}
                              aria-label={isSaved ? 'Unbookmark keyword' : 'Bookmark keyword'}
                            >
                              {isSaved ? (
                                <svg viewBox="0 0 24 24" fill="currentColor" className="keyword-action-svg bookmark-filled">
                                  <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
                                </svg>
                              ) : (
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="keyword-action-svg">
                                  <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
                                </svg>
                              )}
                            </button>
                          </div>
                        </div>

                        {k.definition && (
                          <p className="keyword-item-def">{k.definition}</p>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </ModalDialog>
  );
};
