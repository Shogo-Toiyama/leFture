import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { X, Upload, ChevronRight, Mic, BookOpen, AlertCircle, Calendar } from 'lucide-react';
import { createDraftLecture } from '../../lib/lectures';
import { getCreditSummary } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { InsufficientCreditsError, uploadRecordingAndAnalyze, type UploadProgress } from '../../lib/upload';
import { useProfile } from '../../hooks/useProfile';
import { useAiConsent } from '../../context/AiConsentContext';
import { useCourses } from '../../hooks/useCourses';
import { useLanguage } from '../../i18n/LanguageContext';
import { CoursePickerModal } from './CoursePickerModal';
import { CourseIconGlyph } from '../../lib/courseIcons';
import { LanguageSelectionSheet } from '../account/LanguageSelectionSheet';
import { AccountSuspendedNotice } from '../AccountSuspendedNotice';

const ACCEPTED_EXTENSIONS = '.mp3,.m4a,.wav,.aac,.aiff,.caf,.flac,.ogg';

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
  const inputRef = useRef<HTMLInputElement>(null);

  const [selectedCourseId, setSelectedCourseId] = useState<string | null>(initialCourseId ?? null);
  const [coursePickerOpen, setCoursePickerOpen] = useState(false);
  const [langSheetOpen, setLangSheetOpen] = useState(false);

  const [file, setFile] = useState<File | null>(null);
  const [dragging, setDragging] = useState(false);
  const [title, setTitle] = useState('');
  const [lectureDatetime, setLectureDatetime] = useState<string>(() => formatDatetimeLocal());
  const [recordingLanguage, setRecordingLanguage] = useState('ja');
  const [progress, setProgress] = useState<UploadProgress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [credits, setCredits] = useState<number | null>(null);
  const [hasPlan, setHasPlan] = useState(true);
  const [suspended, setSuspended] = useState(false);

  // Sync initialCourseId when modal opens
  useEffect(() => {
    if (open) {
      setSelectedCourseId(initialCourseId ?? null);
      setFile(null);
      setTitle('');
      setLectureDatetime(formatDatetimeLocal());
      setProgress(null);
      setError(null);
      setSubmitting(false);
    }
  }, [open, initialCourseId]);

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

  // Close on Escape key if not submitting
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

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!selectedCourseId) {
      setError(t('uploadSelectCourseError'));
      return;
    }
    if (!file) {
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
      const isoDatetime = lectureDatetime ? new Date(lectureDatetime).toISOString() : new Date().toISOString();
      const lecture = await createDraftLecture({
        courseId: selectedCourseId,
        title,
        lectureDatetime: isoDatetime,
        recordingLanguage,
        displayLanguage: displayLang,
      });

      try {
        await uploadRecordingAndAnalyze(lecture.id, file, setProgress);
      } catch (err) {
        if (err instanceof InsufficientCreditsError) {
          onClose();
          navigate(`/lectures/${lecture.id}`, { state: { analysisBlockedReason: err.message } });
          return;
        }
        throw err;
      }

      onClose();
      navigate(`/lectures/${lecture.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : t('uploadFailed'));
      setSubmitting(false);
      setProgress(null);
    }
  };

  return (
    <div
      className="upload-modal-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget && !submitting) {
          onClose();
        }
      }}
    >
      <div className="upload-modal-container" role="dialog" aria-modal="true">
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

          {/* Form wrapper */}
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

              {/* 3. Lecture Date & Time */}
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

              {/* 4. Recording Language (アカウントページと統一されたセレクター) */}
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
              <button
                type="button"
                className="upload-cancel-btn"
                onClick={onClose}
                disabled={submitting}
              >
                {t('cancel')}
              </button>
              <button
                type="submit"
                className="upload-submit-btn"
                disabled={submitting || !file || !selectedCourseId || blocked}
              >
                {submitting ? t('uploadSubmitting') : t('uploadSubmit')}
              </button>
            </div>
          </form>
        </div>
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
