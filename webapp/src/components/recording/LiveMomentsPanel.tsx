import React, { useState } from 'react';
import { Star, HelpCircle, Bookmark, NotebookPen, Lightbulb, X, Send } from 'lucide-react';
import { useSystemRecording } from '../../context/SystemRecordingContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { formatMmSs } from './formatRecordingTime';

/**
 * 録音ページの「ライブ」タブ: リアクション3つ + メモ + タイムライン。
 * Flutter版(recording_page.dart の _LiveTab / _ReactionRow / _NoteInputRow / _MomentsTimeline)
 * と同じ並び・アイコン・色。リアルタイム文字起こしはまだ無い。
 */

type ReactionType = 'interesting' | 'difficult' | 'revisit';

const REACTIONS: ReactionType[] = ['interesting', 'difficult', 'revisit'];

function useMomentDisplay() {
  const { t } = useLanguage();
  return (momentType: string): { Icon: typeof Star; color: string; label: string } => {
    switch (momentType) {
      case 'interesting':
        return { Icon: Star, color: 'var(--gold)', label: t('recMomentInteresting') };
      case 'difficult':
        return { Icon: HelpCircle, color: 'var(--rec-cosmic-blue)', label: t('recMomentDifficult') };
      case 'revisit':
        return { Icon: Bookmark, color: 'var(--rec-growth-green)', label: t('recMomentRevisit') };
      case 'note':
        return { Icon: NotebookPen, color: 'var(--comet)', label: t('recMomentNote') };
      default:
        return { Icon: Lightbulb, color: 'var(--comet)', label: momentType };
    }
  };
}

export const LiveMomentsPanel: React.FC = () => {
  const { t } = useLanguage();
  const { phase, moments, addReaction, addNote, deleteMoment } = useSystemRecording();
  const display = useMomentDisplay();
  const [note, setNote] = useState('');

  // Flutter版と同じく、録音中・一時停止中だけ押せる
  const canInteract = phase === 'recording' || phase === 'paused';
  const reactionLabel: Record<ReactionType, string> = {
    interesting: t('recReactionInteresting'),
    difficult: t('recReactionDifficult'),
    revisit: t('recReactionRevisit'),
  };

  const submitNote = () => {
    if (!canInteract || !note.trim()) return;
    addNote(note);
    setNote('');
  };

  return (
    <div className="rec-live">
      <div className="rec-live-status">
        <span className={`rec-live-dot ${phase === 'recording' ? 'is-on' : ''}`} aria-hidden="true" />
        <span>
          {phase === 'recording'
            ? t('recStatusRecording')
            : phase === 'paused'
              ? t('recStatusPaused')
              : t('recLiveNotRecording')}
        </span>
      </div>

      <div className="rec-timeline">
        {moments.length === 0 ? (
          <p className="rec-timeline-empty">{t('recMomentsEmptyHint')}</p>
        ) : (
          <ul className="rec-timeline-list">
            {[...moments].reverse().map((m) => {
              const { Icon, color, label } = display(m.momentType);
              return (
                <li key={m.id} className="rec-timeline-item">
                  <Icon size={16} style={{ color }} className="rec-timeline-icon" />
                  <span className="rec-timeline-time">{formatMmSs(m.timestampSec)}</span>
                  <span className="rec-timeline-text">{m.noteText ?? label}</span>
                  {canInteract && (
                    <button
                      type="button"
                      className="rec-timeline-delete"
                      onClick={() => deleteMoment(m.id)}
                      aria-label={t('recMomentDelete')}
                    >
                      <X size={14} />
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="rec-reactions">
        {REACTIONS.map((type) => {
          const { Icon, color } = display(type);
          return (
            <button
              key={type}
              type="button"
              className="rec-reaction-btn"
              onClick={() => addReaction(type)}
              disabled={!canInteract}
            >
              <Icon size={22} style={{ color }} />
              <span>{reactionLabel[type]}</span>
            </button>
          );
        })}
      </div>

      <form
        className="rec-note-row"
        onSubmit={(e) => {
          e.preventDefault();
          submitNote();
        }}
      >
        <input
          type="text"
          className="rec-note-input"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder={t('recNoteInputHint')}
          disabled={!canInteract}
          maxLength={500}
        />
        <button type="submit" className="rec-note-send" disabled={!canInteract || !note.trim()} aria-label={t('recNoteSend')}>
          <Send size={18} />
        </button>
      </form>
    </div>
  );
};
