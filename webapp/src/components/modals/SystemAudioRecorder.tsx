import React, { useEffect, useRef, useState } from 'react';
import { MonitorSpeaker, Square, Trash2, AlertCircle } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CaptureCancelledError,
  NoSystemAudioError,
  ScreenPermissionError,
  isSystemAudioCaptureSupported,
  startSystemAudioCapture,
  type SystemAudioCapture,
} from '../../lib/systemAudioCapture';

/** この秒数ずっと無音なら「音が入っていません」と出す */
const SILENCE_WARNING_SECONDS = 60;
const SILENCE_DB = -50;

function formatElapsed(totalSeconds: number): string {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = Math.floor(totalSeconds % 60);
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

type Phase = 'idle' | 'starting' | 'recording' | 'stopping';

export interface SystemAudioRecorderProps {
  disabled?: boolean;
  /** 録音中かどうか(録音中はモーダルを閉じられないようにするため) */
  onActiveChange: (active: boolean) => void;
  onRecorded: (file: File, sessionId: string, startedAt: Date) => void;
}

export const SystemAudioRecorder: React.FC<SystemAudioRecorderProps> = ({
  disabled,
  onActiveChange,
  onRecorded,
}) => {
  const { t } = useLanguage();
  const [supported] = useState(isSystemAudioCaptureSupported);
  const [phase, setPhase] = useState<Phase>('idle');
  const [error, setError] = useState<string | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [level, setLevel] = useState(0);
  const [silent, setSilent] = useState(false);
  const captureRef = useRef<SystemAudioCapture | null>(null);
  const stopRef = useRef<() => void>(() => {});

  const active = phase !== 'idle';
  useEffect(() => {
    onActiveChange(active);
  }, [active, onActiveChange]);

  // 録音中はタブを閉じる・再読み込みする前に確認を出す
  useEffect(() => {
    if (!active) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [active]);

  // 経過時間・音量メーター・無音検知
  useEffect(() => {
    if (phase !== 'recording') return;
    let silentSince: number | null = null;
    const timer = window.setInterval(() => {
      const capture = captureRef.current;
      if (!capture) return;
      const now = Date.now();
      setElapsed((now - capture.startedAt.getTime()) / 1000);
      const db = capture.levelDb();
      setLevel(Number.isFinite(db) ? Math.max(0, Math.min(1, (db + 60) / 60)) : 0);
      if (db < SILENCE_DB) {
        silentSince ??= now;
        setSilent(now - silentSince >= SILENCE_WARNING_SECONDS * 1000);
      } else {
        silentSince = null;
        setSilent(false);
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, [phase]);

  // 録音中にモーダルごと消えた場合でも、録音とマイク/共有は止める(保存済みの分は復元できる)
  useEffect(() => {
    return () => captureRef.current?.abort();
  }, []);

  const stop = async () => {
    const capture = captureRef.current;
    if (!capture) return;
    setPhase('stopping');
    try {
      const file = await capture.stop();
      captureRef.current = null;
      setPhase('idle');
      onRecorded(file, capture.sessionId, capture.startedAt);
    } catch {
      captureRef.current = null;
      setPhase('idle');
      setError(t('sysAudioRecordingFailed'));
    }
  };
  stopRef.current = () => {
    void stop();
  };

  const start = async () => {
    setError(null);
    setSilent(false);
    setElapsed(0);
    setLevel(0);
    setPhase('starting');
    try {
      // Chromeの「共有を停止」ボタンで止められた場合も、そこまでの録音を使う
      captureRef.current = await startSystemAudioCapture(() => stopRef.current());
      setPhase('recording');
    } catch (err) {
      setPhase('idle');
      if (err instanceof CaptureCancelledError) return;
      setError(
        err instanceof NoSystemAudioError
          ? t('sysAudioNoAudioError')
          : err instanceof ScreenPermissionError
            ? t('sysAudioPermissionError')
            : t('sysAudioStartFailed')
      );
    }
  };

  const discard = () => {
    if (!window.confirm(t('sysAudioDiscardConfirm'))) return;
    const capture = captureRef.current;
    captureRef.current = null;
    void capture?.discard();
    setPhase('idle');
  };

  if (!supported) {
    return (
      <div className="sysaudio-card is-unsupported">
        <MonitorSpeaker size={18} className="sysaudio-unsupported-icon" />
        <span>{t('sysAudioUnsupported')}</span>
      </div>
    );
  }

  if (phase === 'recording' || phase === 'stopping') {
    return (
      <div className="sysaudio-card is-recording">
        <div className="sysaudio-recording-row">
          <span className="sysaudio-rec-dot" aria-hidden="true" />
          <span className="sysaudio-rec-label">{t('sysAudioRecording')}</span>
          <span className="sysaudio-elapsed">{formatElapsed(elapsed)}</span>
        </div>
        <div className="sysaudio-meter" aria-hidden="true">
          <div className="sysaudio-meter-bar" style={{ width: `${Math.round(level * 100)}%` }} />
        </div>
        {silent && (
          <div className="sysaudio-warning">
            <AlertCircle size={16} />
            <span>{t('sysAudioSilentWarning')}</span>
          </div>
        )}
        <p className="sysaudio-note">{t('sysAudioKeepOpenNote')}</p>
        <div className="sysaudio-actions">
          <button type="button" className="sysaudio-discard-btn" onClick={discard} disabled={phase === 'stopping'}>
            <Trash2 size={15} />
            <span>{t('sysAudioDiscard')}</span>
          </button>
          <button type="button" className="sysaudio-stop-btn" onClick={() => void stop()} disabled={phase === 'stopping'}>
            <Square size={14} fill="currentColor" />
            <span>{phase === 'stopping' ? t('sysAudioStopping') : t('sysAudioStop')}</span>
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="sysaudio-card">
      <div className="sysaudio-header">
        <span className="sysaudio-icon">
          <MonitorSpeaker size={20} />
        </span>
        <div className="sysaudio-header-text">
          <strong className="sysaudio-title">{t('sysAudioTitle')}</strong>
          <span className="sysaudio-desc">{t('sysAudioDescription')}</span>
        </div>
      </div>
      <ol className="sysaudio-steps">
        <li>{t('sysAudioStep1')}</li>
        <li>
          <strong>{t('sysAudioStep2')}</strong>
        </li>
        <li>{t('sysAudioStep3')}</li>
      </ol>
      {error && <div className="upload-error-banner">{error}</div>}
      <button
        type="button"
        className="sysaudio-start-btn"
        onClick={() => void start()}
        disabled={disabled || phase === 'starting'}
      >
        <span className="sysaudio-rec-dot" aria-hidden="true" />
        <span>{phase === 'starting' ? t('sysAudioStarting') : t('sysAudioStart')}</span>
      </button>
    </div>
  );
};
