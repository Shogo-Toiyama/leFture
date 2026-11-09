import React from 'react';
import { useLocation } from 'react-router-dom';
import { Mic, Pause, Upload } from 'lucide-react';
import { useSystemRecording } from '../../context/SystemRecordingContext';
import { useUploadModal } from '../../context/UploadModalContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { formatRecordingTime } from './formatRecordingTime';

/**
 * アップロード画面を閉じて録音している間、ヘッダー(AppTopbar)のロゴのすぐ右に出る小さなタイマー。
 * Flutter版のRecordingTimerChip(presentation/widgets/recording_timer_chip.dart)と同じく、
 * 録音中は赤・一時停止中は黄。押すとアップロード画面が録音中の状態で開き直す。
 */
export const RecordingChip: React.FC = () => {
  const { phase, elapsedSeconds, courseId } = useSystemRecording();
  const { isOpen, openUploadModal } = useUploadModal();
  const { t } = useLanguage();
  const location = useLocation();

  const visible =
    phase === 'recording' || phase === 'paused' || phase === 'finishing' || phase === 'ready';
  // アップロード画面が開いている間(/upload のページ版を含む)は、その中に録音が見えているので出さない
  const uploadPageOpen = location.pathname === '/upload' || location.pathname.endsWith('/upload');
  if (!visible || isOpen || uploadPageOpen) return null;

  const variant = phase === 'recording' ? 'is-recording' : phase === 'ready' ? 'is-ready' : 'is-paused';
  const Icon = phase === 'recording' ? Mic : phase === 'ready' ? Upload : Pause;
  const label =
    phase === 'recording'
      ? t('recStatusRecording')
      : phase === 'ready'
        ? t('recChipReady')
        : t('recStatusPaused');

  return (
    <button
      type="button"
      className={`rec-chip ${variant}`}
      onClick={() => openUploadModal(courseId)}
      aria-label={`${label} ${formatRecordingTime(elapsedSeconds)}`}
      title={t('recChipOpen')}
    >
      <Icon size={12} />
      <span className="rec-chip-time">{formatRecordingTime(elapsedSeconds)}</span>
    </button>
  );
};
