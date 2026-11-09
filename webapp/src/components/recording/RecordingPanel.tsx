import React, { useState } from 'react';
import { Mic, Square, Circle, Check, Pause, Trash2, AlertCircle, AlertTriangle } from 'lucide-react';
import {
  useSystemRecording,
  RECORDING_WARNING_SECONDS,
  MAX_RECORDING_SECONDS,
} from '../../context/SystemRecordingContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { AudioWaveform } from './AudioWaveform';
import { formatClock } from './formatRecordingTime';

/**
 * アップロード画面の中に出す「PCの音の録音」パネル(録音中・一時停止中・アップロード待ち)。
 * 部品(タイマー・25本の波形・丸ボタン・状態ピル)はFlutter版RecordingPageと同じ見た目で、
 * 並べ方だけモーダルに収まる横並びにしている。
 */
export const RecordingPanel: React.FC<{ disabled?: boolean }> = ({ disabled }) => {
  const rec = useSystemRecording();
  const { t } = useLanguage();
  const [discardOpen, setDiscardOpen] = useState(false);

  const { phase, elapsedSeconds } = rec;
  const isRecording = phase === 'recording';
  const isPaused = phase === 'paused';
  const busy = phase === 'starting' || phase === 'finishing' || !!disabled;

  const onMicClick = () => {
    if (busy) return;
    if (isRecording) rec.pause();
    else if (isPaused) rec.resume();
  };

  const status = () => {
    if (phase === 'starting') return <span className="rec-status-text">{t('sysAudioStarting')}</span>;
    if (phase === 'finishing') return <span className="rec-status-text">{t('sysAudioStopping')}</span>;
    if (isRecording)
      return (
        <span className="rec-status-pill is-recording">
          <Circle size={11} fill="currentColor" />
          {t('recStatusRecording')}
        </span>
      );
    if (isPaused)
      return (
        <span className="rec-status-pill is-paused">
          <Pause size={12} />
          {t('recStatusPaused')}
        </span>
      );
    return (
      <span className="rec-status-pill is-ready">
        <Check size={12} />
        {t('recStatusReadyToUpload')}
      </span>
    );
  };

  const micIcon = isRecording ? (
    <Square size={34} fill="currentColor" />
  ) : isPaused ? (
    <Circle size={34} fill="currentColor" />
  ) : phase === 'ready' ? (
    <Check size={40} />
  ) : (
    <Mic size={40} />
  );

  return (
    <div className={`rec-panel ${isRecording ? 'is-recording' : ''}`}>
      <div className="rec-panel-main">
        <div className="rec-panel-left">
          <div className={`rec-timer ${isRecording ? 'is-recording' : ''}`}>{formatClock(elapsedSeconds)}</div>
          <div className="rec-status">{status()}</div>
          <AudioWaveform getLevel={rec.getLevel} isRecording={isRecording} />
        </div>
        <button
          type="button"
          className={`rec-mic-btn ${isRecording ? 'is-recording' : ''} ${phase === 'ready' ? 'is-ready' : ''}`}
          onClick={onMicClick}
          disabled={busy || phase === 'ready'}
          aria-label={isRecording ? t('recMicPause') : t('recMicResume')}
        >
          {isRecording && <span className="rec-mic-pulse" aria-hidden="true" />}
          <span className="rec-mic-core">{micIcon}</span>
        </button>
      </div>

      {elapsedSeconds >= RECORDING_WARNING_SECONDS && elapsedSeconds < MAX_RECORDING_SECONDS && (
        <div className="rec-banner is-warning">
          <AlertTriangle size={16} />
          <span>{t('recDurationWarning')}</span>
        </div>
      )}
      {rec.hitDurationLimit && (
        <div className="rec-banner is-warning">
          <AlertTriangle size={16} />
          <span>{t('recDurationLimit')}</span>
        </div>
      )}
      {phase === 'ready' && rec.endedExternally && (
        <div className="rec-banner is-warning">
          <AlertTriangle size={16} />
          <span>{t('recStatusEndedBySharing')}</span>
        </div>
      )}
      {isRecording && rec.silent && (
        <div className="rec-banner is-warning">
          <AlertCircle size={16} />
          <span>{t('sysAudioSilentWarning')}</span>
        </div>
      )}

      {discardOpen ? (
        // 確認ダイアログ(ConfirmModal)はアップロード画面より奥に出てしまうので、その場で確認する
        <div className="rec-discard-confirm" role="alertdialog" aria-label={t('recDiscardDialogTitle')}>
          <span>
            <strong>{t('recDiscardDialogTitle')}</strong> {t('recDiscardDialogMessage')}
          </span>
          <div className="rec-discard-confirm-actions">
            <button type="button" className="rec-btn-ghost" onClick={() => setDiscardOpen(false)}>
              {t('cancel')}
            </button>
            <button
              type="button"
              className="rec-btn-danger"
              onClick={() => {
                setDiscardOpen(false);
                void rec.discard();
              }}
            >
              {t('recDiscardConfirm')}
            </button>
          </div>
        </div>
      ) : (
        <div className="rec-panel-footer">
          <p className="rec-note">{isPaused ? t('recPausedHint') : t('recKeepOpenNote')}</p>
          <button type="button" className="rec-discard-btn" onClick={() => setDiscardOpen(true)} disabled={busy}>
            <Trash2 size={15} />
            {t('recDiscardButton')}
          </button>
        </div>
      )}
    </div>
  );
};
