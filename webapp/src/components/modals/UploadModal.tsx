import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  X,
  Upload,
  ChevronRight,
  Mic,
  BookOpen,
  AlertCircle,
  Calendar,
  MonitorSpeaker,
  RotateCcw,
  Sparkles,
  HelpCircle,
  ChevronDown,
} from 'lucide-react';
import { createDraftLecture } from '../../lib/lectures';
import { getCreditSummary } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { InsufficientCreditsError, uploadRecordingAndAnalyze, type UploadProgress } from '../../lib/upload';
import { insertLectureMoments } from '../../lib/lectureMoments';
import { hasCaptureSucceededBefore, isMacPlatform } from '../../lib/systemAudioCapture';
import { useProfile } from '../../hooks/useProfile';
import { useAiConsent } from '../../context/AiConsentContext';
import { useCourses } from '../../hooks/useCourses';
import { useMediaQuery } from '../../hooks/useMediaQuery';
import { useSystemRecording } from '../../context/SystemRecordingContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { CoursePickerModal } from './CoursePickerModal';
import { CourseIconGlyph } from '../../lib/courseIcons';
import { LanguageSelectionSheet } from '../account/LanguageSelectionSheet';
import { AccountSuspendedNotice } from '../AccountSuspendedNotice';
import { RecordingPanel } from '../recording/RecordingPanel';
import { LiveMomentsPanel } from '../recording/LiveMomentsPanel';

const ACCEPTED_EXTENSIONS = '.mp3,.m4a,.wav,.aac,.aiff,.caf,.flac,.ogg';
/** この幅以上なら、録音中の「ライブ」パネルをフォームの右に並べる(狭いとタブで切り替え) */
const LIVE_SIDE_BY_SIDE_QUERY = '(min-width: 1180px)';

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDatetimeLocal(d: Date = new Date()): string {
  const offset = d.getTimezoneOffset() * 60000;
  return new Date(d.getTime() - offset).toISOString().slice(0, 16);
}

interface LanguageOption {
  code: string;
  nativeName: string;
  englishName: string;
}

const RECORDING_LANGUAGES: LanguageOption[] = [
  { code: 'ja', nativeName: '日本語', englishName: 'Japanese' },
  { code: 'en', nativeName: 'English', englishName: 'English' },
  { code: 'zh', nativeName: '中文', englishName: 'Chinese' },
  { code: 'es', nativeName: 'Español', englishName: 'Spanish' },
  { code: 'fr', nativeName: 'Français', englishName: 'French' },
  { code: 'de', nativeName: 'Deutsch', englishName: 'German' },
  { code: 'ko', nativeName: '한국語', englishName: 'Korean' },
];

export interface UploadModalProps {
  open: boolean;
  onClose: () => void;
  initialCourseId?: string | null;
}

/**
 * 「Upload a Recording」。音声ファイルのアップロードが基本で、その下から
 * PCの音(Zoomの授業など)の録音も始められる。録音の実体はSystemRecordingContextが
 * 持っているので、録音中にこの画面を閉じても録音は続き、上部のタイマーから戻れる。
 * 録音中・一時停止中は右側(狭い画面ではタブ)に「ライブ」(リアクション/メモ)が出る。
 */
export const UploadModal: React.FC<UploadModalProps> = ({
  open,
  onClose,
  initialCourseId,
}) => {
  const navigate = useNavigate();
  const { language, t } = useLanguage();
  const { profile, refetch: refetchProfile } = useProfile();
  const { requestConsent } = useAiConsent();
  const { courses } = useCourses();
  const rec = useSystemRecording();
  const sideBySide = useMediaQuery(LIVE_SIDE_BY_SIDE_QUERY);
  const inputRef = useRef<HTMLInputElement>(null);

  const [localCourseId, setLocalCourseId] = useState<string | null>(initialCourseId ?? null);
  const [coursePickerOpen, setCoursePickerOpen] = useState(false);
  const [langSheetOpen, setLangSheetOpen] = useState(false);

  const [file, setFile] = useState<File | null>(null);
  const [dragging, setDragging] = useState(false);
  const [localTitle, setLocalTitle] = useState('');
  const [lectureDatetime, setLectureDatetime] = useState<string>(() => formatDatetimeLocal());
  const [recordingLanguage, setRecordingLanguage] = useState('ja');
  const [progress, setProgress] = useState<UploadProgress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [credits, setCredits] = useState<number | null>(null);
  const [hasPlan, setHasPlan] = useState(true);
  const [suspended, setSuspended] = useState(false);
  const [mobileTab, setMobileTab] = useState<'upload' | 'live'>('upload');
  // 録音のアップロードが途中で失敗したとき、やり直しで講義を二重に作らないために覚えておく
  const [createdLectureId, setCreatedLectureId] = useState<string | null>(null);
  // Macの初回セットアップの手順(小さなヘルプボタンで開閉)。初回のMacではボタンだけ目立たせる
  const [isMac] = useState(isMacPlatform);
  const [firstTimeOnMac, setFirstTimeOnMac] = useState(false);
  const [setupOpen, setSetupOpen] = useState(false);

  // 録音を始めてからは、コース・タイトルは録音側(画面を閉じても残る)の値を使う
  const recordingMode = rec.phase !== 'idle';
  const liveVisible = rec.phase === 'recording' || rec.phase === 'paused';
  const selectedCourseId = recordingMode ? rec.courseId : localCourseId;
  const setSelectedCourseId = (id: string | null) => (recordingMode ? rec.setCourseId(id) : setLocalCourseId(id));
  const title = recordingMode ? rec.title : localTitle;
  const setTitle = (value: string) => (recordingMode ? rec.setTitle(value) : setLocalTitle(value));

  // Sync initialCourseId when modal opens
  useEffect(() => {
    if (open) {
      setLocalCourseId(initialCourseId ?? null);
      setFile(null);
      setLocalTitle('');
      setLectureDatetime(formatDatetimeLocal());
      setProgress(null);
      setError(null);
      setSubmitting(false);
      setMobileTab('upload');
      setFirstTimeOnMac(isMac && !hasCaptureSucceededBefore());
      setSetupOpen(false);
      void rec.refreshLeftover();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initialCourseId]);

  // 録音が終わった(破棄・アップロード待ち)らライブタブから戻す
  useEffect(() => {
    if (!liveVisible) setMobileTab('upload');
  }, [liveVisible]);

  // Sync recording language with profile settings
  useEffect(() => {
    if (profile?.metadata?.recording_language) {
      setRecordingLanguage(profile.metadata.recording_language);
    } else {
      setRecordingLanguage(language);
    }
  }, [profile, language]);

  // Check credits
  useEffect(() => {
    if (!open) return;
    getCreditSummary()
      .then((summary) => {
        setCredits(toDisplayCredits(summary.credit_balance));
        setHasPlan(summary.has_active_plan);
        setSuspended(summary.suspended);
      })
      .catch(() => setCredits(null));
  }, [open]);

  // Close on Escape key if not submitting (録音中に閉じても録音は続く)
  useEffect(() => {
    if (!open) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, submitting, onClose]);

  if (!open) return null;

  const blocked = suspended || (credits !== null && (!hasPlan || credits <= 0));
  const selectedCourse = courses.find((c) => c.id === selectedCourseId);
  const recordingBusy = rec.phase === 'starting' || rec.phase === 'finishing';
  // Flutter版と同じく、録音は一時停止中(またはもう再開できない録音済み)のときだけアップロードできる
  const recordingUploadable = rec.phase === 'paused' || rec.phase === 'ready';
  const canSubmit =
    !submitting &&
    !blocked &&
    !!selectedCourseId &&
    (recordingMode ? recordingUploadable && !recordingBusy : !!file);

  const pickFile = (next: File | null) => {
    setFile(next);
  };

  const handleDrop = (event: React.DragEvent) => {
    event.preventDefault();
    setDragging(false);
    const dropped = event.dataTransfer.files?.[0];
    if (dropped) pickFile(dropped);
  };

  const getLanguageLabel = (code: string) => {
    const found = RECORDING_LANGUAGES.find((l) => l.code === code);
    if (!found) return code;
    return `${found.nativeName} (${found.englishName})`;
  };

  const stepLabelMap: Record<UploadProgress['step'], string> = {
    'requesting-url': t('uploadPreparing'),
    uploading: t('uploadUploading'),
    finalizing: t('uploadFinalizing'),
    'starting-analysis': t('uploadStartingAnalysis'),
    done: t('uploadDone'),
  };

  const recordingErrorText: Record<NonNullable<typeof rec.error>, string> = {
    noAudio: t('sysAudioNoAudioError'),
    permission: t('sysAudioPermissionError'),
    startFailed: t('sysAudioStartFailed'),
    recordingFailed: t('sysAudioRecordingFailed'),
  };

  const startRecording = () => {
    setError(null);
    void rec.start({ courseId: localCourseId, title: localTitle });
  };

  const finishNavigate = (lectureId: string, blockedReason?: string) => {
    onClose();
    navigate(`/lectures/${lectureId}`, blockedReason ? { state: { analysisBlockedReason: blockedReason } } : undefined);
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!selectedCourseId) {
      setError(t('uploadSelectCourseError'));
      return;
    }
    if (!recordingMode && !file) {
      setError(t('uploadSelectAudioError'));
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      // 録音の音声・プロフィール情報をAIサービスへ送ることへの同意(アカウント単位)。
      // 版が上がったときは、前の版に同意した人にもう一度聞く。断られたら何もアップロードしない
      if (!(await requestConsent('recording'))) {
        setSubmitting(false);
        return;
      }
      const displayLang = profile?.metadata?.display_language || language;

      if (recordingMode) {
        // ---- PCの音の録音 ----
        const recording = rec.phase === 'ready' ? rec.ready : await rec.finish();
        if (!recording) {
          setSubmitting(false);
          return;
        }
        let lectureId = createdLectureId;
        if (!lectureId) {
          const lecture = await createDraftLecture({
            courseId: selectedCourseId,
            title,
            // 講義日時は録音を始めた時刻
            lectureDatetime: recording.startedAt.toISOString(),
            recordingLanguage,
            displayLanguage: displayLang,
          });
          lectureId = lecture.id;
          setCreatedLectureId(lectureId);
          // リアクション/メモが保存できなくても録音のアップロードは止めない
          await insertLectureMoments(lectureId, rec.moments).catch((err) => {
            console.warn('[upload] failed to save reactions/notes', err);
          });
        }
        try {
          await uploadRecordingAndAnalyze(lectureId, recording.file, setProgress, {
            startAnalysis: rec.autoStartAnalysis,
          });
        } catch (err) {
          if (err instanceof InsufficientCreditsError) {
            await rec.completeUpload();
            setCreatedLectureId(null);
            finishNavigate(lectureId, err.message);
            return;
          }
          throw err;
        }
        await rec.completeUpload();
        setCreatedLectureId(null);
        finishNavigate(lectureId);
        return;
      }

      // ---- 音声ファイル ----
      const isoDatetime = lectureDatetime ? new Date(lectureDatetime).toISOString() : new Date().toISOString();
      const lecture = await createDraftLecture({
        courseId: selectedCourseId,
        title,
        lectureDatetime: isoDatetime,
        recordingLanguage,
        displayLanguage: displayLang,
      });

      try {
        await uploadRecordingAndAnalyze(lecture.id, file!, setProgress, { startAnalysis: rec.autoStartAnalysis });
      } catch (err) {
        if (err instanceof InsufficientCreditsError) {
          finishNavigate(lecture.id, err.message);
          return;
        }
        throw err;
      }

      finishNavigate(lecture.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : t('uploadFailed'));
      setSubmitting(false);
      setProgress(null);
    }
  };

  const leftoverMinutes = rec.leftover ? Math.max(1, Math.round((rec.leftover.bytes * 8) / 64_000 / 60)) : 0;

  // ---- 音声の入力欄: 録音中は録音パネル、それ以外はファイル欄(大) + 録音カード(小) ----
  const sourceSection = recordingMode ? (
    <div className="upload-form-group">
      <RecordingPanel disabled={submitting} />
    </div>
  ) : (
    <>
      {rec.leftover && !file && (
        <div className="rec-leftover">
          <RotateCcw size={16} className="rec-leftover-icon" />
          <span className="rec-leftover-text">
            {t('sysAudioLeftoverFound')
              .replace('{date}', new Date(rec.leftover.startedAt).toLocaleString(language))
              .replace('{minutes}', String(leftoverMinutes))}
          </span>
          <div className="rec-leftover-actions">
            <button type="button" className="rec-btn-ghost" onClick={() => void rec.discardLeftover()}>
              {t('sysAudioDiscard')}
            </button>
            <button type="button" className="rec-btn-gold" onClick={() => void rec.restoreLeftover()}>
              {t('sysAudioLeftoverUse')}
            </button>
          </div>
        </div>
      )}

      {/* 2. Drag & Drop Audio Upload Zone */}
      <div className="upload-form-group">
        <div
          className={`upload-dropzone ${dragging ? 'is-dragging' : ''} ${file ? 'has-file' : ''}`}
          onDragOver={(e) => {
            e.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={handleDrop}
          onClick={() => inputRef.current?.click()}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') inputRef.current?.click();
          }}
        >
          <input
            ref={inputRef}
            type="file"
            accept={ACCEPTED_EXTENSIONS}
            hidden
            onChange={(e) => pickFile(e.target.files?.[0] ?? null)}
          />
          {file ? (
            <div className="upload-dropzone-file-card">
              <div className="upload-dropzone-file-icon">
                <Upload size={22} color="var(--gold)" />
              </div>
              <div className="upload-dropzone-file-details">
                <strong className="upload-dropzone-filename">{file.name}</strong>
                <span className="upload-dropzone-filesize">
                  {formatBytes(file.size)} ·{' '}
                  <span className="upload-dropzone-change-hint">
                    {t('uploadClickToChangeFile')}
                  </span>
                </span>
              </div>
            </div>
          ) : (
            <div className="upload-dropzone-empty">
              <div className="upload-dropzone-cloud-icon">
                <Upload size={32} />
              </div>
              <strong className="upload-dropzone-prompt">
                {t('uploadDropAudioHere')}
              </strong>
              <span className="upload-dropzone-formats">
                {t('uploadDropFormats')}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* 2b. PCの音を録音(ファイル未選択のとき、小さめに) */}
      {!file && rec.supported && (
        <div className="upload-form-group">
          <div className="sysaudio-divider">{t('sysAudioOr')}</div>
          <div className="sysaudio-card">
            <div className="sysaudio-card-row">
              <span className="sysaudio-entry-icon">
                <MonitorSpeaker size={20} />
              </span>
              <span className="sysaudio-entry-text">
                <strong>{t('sysAudioTitle')}</strong>
                <span>{t('sysAudioDescription')}</span>
              </span>
              <button
                type="button"
                className="sysaudio-start-btn"
                onClick={startRecording}
                disabled={submitting || blocked || rec.phase !== 'idle'}
              >
                <span className="sysaudio-start-dot" aria-hidden="true" />
                {t('sysAudioStart')}
              </button>
            </div>
            <ol className="sysaudio-steps">
              <li>{t('sysAudioStep1')}</li>
              <li>
                <strong>{t('sysAudioStep2')}</strong>
              </li>
              <li>{t('sysAudioStep3')}</li>
            </ol>
            {rec.error && rec.error !== 'permission' && (
              <div className="upload-error-banner">{recordingErrorText[rec.error]}</div>
            )}

            {/* Macの初回セットアップ: ふだんは閉じた小さなボタン。許可が原因で失敗したときだけ自動で開く */}
            {isMac && (
              <div className="sysaudio-setup">
                <button
                  type="button"
                  className={`sysaudio-setup-toggle ${firstTimeOnMac ? 'is-first-time' : ''}`}
                  onClick={() => setSetupOpen((v) => !v)}
                  aria-expanded={setupOpen || rec.error === 'permission'}
                >
                  <HelpCircle size={14} />
                  {t('sysAudioSetupHelp')}
                  <ChevronDown
                    size={14}
                    className={`sysaudio-setup-chevron ${setupOpen || rec.error === 'permission' ? 'is-open' : ''}`}
                  />
                </button>
                {(setupOpen || rec.error === 'permission') && (
                  <div className={`sysaudio-mac-setup ${rec.error === 'permission' ? 'is-error' : ''}`}>
                    <strong>{rec.error === 'permission' ? t('sysAudioPermissionError') : t('sysAudioSetupIntro')}</strong>
                    <ol>
                      <li>{t('sysAudioSetupStep1')}</li>
                      <li>{t('sysAudioSetupStep2')}</li>
                      <li>{t('sysAudioSetupStep3')}</li>
                      <li>{t('sysAudioSetupStep4')}</li>
                    </ol>
                    <span className="sysaudio-setup-footnote">{t('sysAudioSetupFootnote')}</span>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );

  const showLiveTab = liveVisible && !sideBySide && mobileTab === 'live';

  return (
    <div
      className="upload-modal-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget && !submitting) {
          onClose();
        }
      }}
    >
      <div
        className={`upload-modal-container ${liveVisible && sideBySide ? 'has-live' : ''}`}
        role="dialog"
        aria-modal="true"
      >
        <div className="upload-modal-card">
          {/* Header */}
          <div className="upload-modal-header">
            <div className="upload-modal-header-info">
              <h2 className="upload-modal-title">{t('uploadTitle')}</h2>
              <p className="upload-modal-subtitle">{t('uploadModalSubtitle')}</p>
            </div>
            <button
              type="button"
              className="upload-modal-close-btn"
              onClick={onClose}
              disabled={submitting}
              aria-label={t('close')}
            >
              <X size={26} strokeWidth={2} />
            </button>
          </div>

          {/* 狭い画面: 録音中だけ「アップロード | ライブ」のタブ */}
          {liveVisible && !sideBySide && (
            <div className="upload-live-tabs" role="tablist">
              <button
                type="button"
                role="tab"
                aria-selected={mobileTab === 'upload'}
                className={`upload-live-tab ${mobileTab === 'upload' ? 'is-active' : ''}`}
                onClick={() => setMobileTab('upload')}
              >
                <Upload size={16} />
                {t('uploadTabForm')}
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={mobileTab === 'live'}
                className={`upload-live-tab ${mobileTab === 'live' ? 'is-active' : ''}`}
                onClick={() => setMobileTab('live')}
              >
                <Sparkles size={16} />
                {t('recTabLive')}
                {rec.moments.length > 0 && <span className="upload-live-tab-count">{rec.moments.length}</span>}
              </button>
            </div>
          )}

          {showLiveTab ? (
            <div className="upload-modal-body">
              <LiveMomentsPanel />
            </div>
          ) : (
            <form className="upload-modal-form" onSubmit={handleSubmit}>
              {/* Scrollable Body Content */}
              <div className="upload-modal-body">
                {suspended && <AccountSuspendedNotice />}
                {blocked && !suspended && (
                  <div className="upload-notice-error">
                    <AlertCircle size={18} className="upload-notice-icon" />
                    <span>
                      {hasPlan ? t('uploadNoCreditsError') : t('uploadNoPlanError')}
                    </span>
                    <button
                      type="button"
                      className="upload-notice-link"
                      onClick={() => {
                        onClose();
                        navigate('/account/credits');
                      }}
                    >
                      {t('uploadManageCredits')}
                    </button>
                  </div>
                )}

                {/* 1. Course Selector (一番上) */}
                <div className="upload-form-group">
                  <button
                    type="button"
                    className={`upload-course-selector-box ${!selectedCourse ? 'is-empty' : ''}`}
                    onClick={() => setCoursePickerOpen(true)}
                    disabled={submitting}
                  >
                    <div className="upload-course-selector-left">
                      <span className="upload-course-icon-badge">
                        {selectedCourse ? (
                          <CourseIconGlyph
                            icon={selectedCourse.metadata?.icon_name as string}
                            color={selectedCourse.metadata?.color as string}
                            className="upload-course-glyph"
                          />
                        ) : (
                          <BookOpen size={18} color="var(--comet)" />
                        )}
                      </span>
                      <div className="upload-course-text">
                        <span className="upload-course-title">
                          {selectedCourse
                            ? selectedCourse.course_title
                            : t('uploadSelectCoursePlaceholder')}
                        </span>
                        {selectedCourse?.course_code && (
                          <span className="upload-course-code">{selectedCourse.course_code}</span>
                        )}
                      </div>
                    </div>
                    <div className="upload-course-selector-right">
                      <span className="upload-course-change-text">
                        {selectedCourse ? t('changeCourse') : t('selectCourse')}
                      </span>
                      <ChevronRight size={16} />
                    </div>
                  </button>
                </div>

                {sourceSection}

                {/* 3. Lecture Date & Time (録音の場合は録音を始めた時刻を使う) */}
                {!recordingMode && (
                  <div className="upload-form-group">
                    <label className="upload-field-label">
                      <Calendar size={14} className="upload-field-label-icon" />
                      <span>{t('uploadLectureDateTime')}</span>
                    </label>
                    <input
                      type="datetime-local"
                      className="upload-text-input upload-datetime-input"
                      value={lectureDatetime}
                      onChange={(e) => setLectureDatetime(e.target.value)}
                      disabled={submitting}
                      required
                    />
                  </div>
                )}

                {/* 4. Title Input */}
                <div className="upload-form-group">
                  <input
                    type="text"
                    className="upload-text-input"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    placeholder={t('uploadTitlePlaceholder')}
                    disabled={submitting}
                  />
                </div>

                {/* 5. Recording Language (アカウントページと統一されたセレクター) */}
                <div className="upload-form-group">
                  <button
                    type="button"
                    className="upload-language-selector-row"
                    onClick={() => setLangSheetOpen(true)}
                    disabled={submitting}
                  >
                    <div className="upload-language-selector-left">
                      <span className="upload-language-icon-wrap">
                        <Mic size={17} />
                      </span>
                      <div className="upload-language-text">
                        <span className="upload-language-title">{t('recordingLanguage')}</span>
                        <span className="upload-language-value">{getLanguageLabel(recordingLanguage)}</span>
                      </div>
                    </div>
                    <ChevronRight size={18} className="upload-language-chevron" />
                  </button>
                </div>

                {/* 6. Auto-start analysis (アップロードだけして後で解析を始めることもできる) */}
                <div className="upload-form-group">
                  <label className="upload-autostart-row">
                    <span className="upload-autostart-text">
                      <span className="upload-autostart-title">{t('recAutoStartTitle')}</span>
                      <span className="upload-autostart-subtitle">{t('recAutoStartSubtitle')}</span>
                    </span>
                    <input
                      type="checkbox"
                      role="switch"
                      className="rec-switch"
                      checked={rec.autoStartAnalysis}
                      onChange={(e) => rec.setAutoStartAnalysis(e.target.checked)}
                      disabled={submitting}
                    />
                  </label>
                </div>

                {error && <div className="upload-error-banner">{error}</div>}

                {/* Progress Track */}
                {progress && (
                  <div className="upload-progress-container">
                    <div className="upload-progress-header">
                      <span className="upload-progress-step">{stepLabelMap[progress.step]}</span>
                      {progress.ratio !== undefined && (
                        <span className="upload-progress-percent">
                          {Math.round(progress.ratio * 100)}%
                        </span>
                      )}
                    </div>
                    <div className="upload-progress-track">
                      <div
                        className="upload-progress-bar"
                        style={{
                          width:
                            progress.ratio !== undefined
                              ? `${Math.round(progress.ratio * 100)}%`
                              : '100%',
                        }}
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Footer Actions (モーダルの最下部に常に配置) */}
              <div className="upload-modal-footer">
                {recordingMode && rec.phase === 'recording' && (
                  <span className="upload-footer-hint">{t('recPauseToUploadHint')}</span>
                )}
                <button
                  type="button"
                  className="upload-cancel-btn"
                  onClick={onClose}
                  disabled={submitting}
                >
                  {recordingMode ? t('close') : t('cancel')}
                </button>
                <button
                  type="submit"
                  className="upload-submit-btn"
                  disabled={!canSubmit}
                >
                  {submitting
                    ? t('uploadSubmitting')
                    : rec.autoStartAnalysis
                      ? t('uploadSubmit')
                      : t('uploadSubmitWithoutAnalysis')}
                </button>
              </div>
            </form>
          )}
        </div>

        {/* 広い画面: 録音中だけ右側に「ライブ」パネル */}
        {liveVisible && sideBySide && (
          <aside className="upload-live-panel" aria-label={t('recTabLive')}>
            <div className="upload-live-panel-header">
              <Sparkles size={16} />
              <span>{t('recTabLive')}</span>
            </div>
            <div className="upload-live-panel-body">
              <LiveMomentsPanel />
            </div>
          </aside>
        )}
      </div>

      {/* Course Picker Modal */}
      {coursePickerOpen && (
        <CoursePickerModal
          initialSelectedCourseId={selectedCourseId}
          onClose={() => setCoursePickerOpen(false)}
          onSelectCourse={(newCourseId) => {
            if (newCourseId) setSelectedCourseId(newCourseId);
          }}
        />
      )}

      {/* Language Selection Sheet (アカウントページと完全統一) */}
      {langSheetOpen && (
        <LanguageSelectionSheet
          open={langSheetOpen}
          onClose={() => setLangSheetOpen(false)}
          mode="recording"
          profile={profile}
          onUpdated={async () => {
            await refetchProfile();
          }}
        />
      )}
    </div>
  );
};
