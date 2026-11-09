import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import {
  CaptureCancelledError,
  NoSystemAudioError,
  ScreenPermissionError,
  displayLevelFromRms,
  isSystemAudioCaptureSupported,
  markCaptureSucceeded,
  startSystemAudioCapture,
  systemAudioFileName,
  type SystemAudioCapture,
} from '../lib/systemAudioCapture';
import {
  deleteRecordingSession,
  listRecordingSessions,
  loadRecordingFile,
  updateRecordingSessionMoments,
  type RecordingMoment,
  type RecordingSessionMeta,
} from '../lib/recordingStore';

/**
 * PCの音の録音(録音ページ /record)の状態をアプリ全体で持つ。
 *
 * 録音そのもの(MediaRecorder・画面共有)はここが握っているので、録音ページを閉じて
 * 他のページへ移っても録音は続く(webappはページ遷移で再読み込みしないため)。
 * Flutter版のRecordingController(application/recording/recording_controller.dart)
 * に合わせ、開始 → 一時停止/再開 → (一時停止中に)アップロード、の流れにしている。
 *
 * phase:
 * - idle: 何もしていない
 * - starting: 共有ダイアログの応答待ち
 * - recording / paused: 録音中 / 一時停止中(再開できる)
 * - finishing: 録音を閉じてファイルを作っている
 * - ready: ファイルができていて、もう再開はできない(アップロード待ち)。
 *   共有が外から止められた場合・前回の録音を復元した場合・アップロードが失敗した場合
 */
export type SystemRecordingPhase = 'idle' | 'starting' | 'recording' | 'paused' | 'finishing' | 'ready';

export type SystemRecordingError = 'noAudio' | 'permission' | 'startFailed' | 'recordingFailed';

/** Flutter版と同じ上限(kMaxRecordingSeconds = 210分)。到達したら自動で一時停止する */
export const MAX_RECORDING_SECONDS = 210 * 60;
/** Flutter版のkRecordingDurationWarningSeconds(3時間)。ここから警告を出す */
export const RECORDING_WARNING_SECONDS = 3 * 60 * 60;
/** この秒数ずっと無音なら警告を出す(画面共有で音声をONにし忘れた等) */
const SILENCE_WARNING_SECONDS = 60;

export interface ReadyRecording {
  file: File;
  sessionId: string;
  startedAt: Date;
}

interface SystemRecordingContextValue {
  supported: boolean;
  phase: SystemRecordingPhase;
  /** 録音した秒数(一時停止中は進まない)。音声ファイル上の位置と一致する */
  elapsedSeconds: number;
  error: SystemRecordingError | null;
  /** 画面共有がページの外(Chromeの「共有を停止」等)で終わった */
  endedExternally: boolean;
  /** 上限に達して自動で一時停止した */
  hitDurationLimit: boolean;
  silent: boolean;
  moments: RecordingMoment[];
  ready: ReadyRecording | null;
  startedAt: Date | null;
  /** 現在の音量(0〜1、Flutter版と同じ計算)。描画側がポーリングする(毎回再描画させないため) */
  getLevel: () => number;

  // 録音ページの設定(ページを離れても保持する)
  courseId: string | null;
  setCourseId: (id: string | null) => void;
  title: string;
  setTitle: (title: string) => void;
  autoStartAnalysis: boolean;
  setAutoStartAnalysis: (value: boolean) => void;

  /** 録音を始める。courseId/titleはアップロード画面で入力済みの値を引き継ぐ */
  start: (initial?: { courseId: string | null; title: string }) => Promise<void>;
  pause: () => void;
  resume: () => void;
  /** 録音を閉じてアップロードできるファイルにする(ready状態にする) */
  finish: () => Promise<ReadyRecording | null>;
  discard: () => Promise<void>;
  /** アップロードが成功した後に呼ぶ。バックアップを消してidleへ戻す */
  completeUpload: () => Promise<void>;
  addReaction: (momentType: 'interesting' | 'difficult' | 'revisit') => void;
  addNote: (text: string) => void;
  deleteMoment: (id: string) => void;

  /** 前回アップロードされずに残っている録音 */
  leftover: RecordingSessionMeta | null;
  refreshLeftover: () => Promise<void>;
  restoreLeftover: () => Promise<void>;
  discardLeftover: () => Promise<void>;
}

const SystemRecordingContext = createContext<SystemRecordingContextValue | undefined>(undefined);

const AUTO_START_KEY = 'lefture.recording.autoStartAnalysis';

function readAutoStart(): boolean {
  try {
    return localStorage.getItem(AUTO_START_KEY) !== 'false';
  } catch {
    return true;
  }
}

export const SystemRecordingProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [supported] = useState(isSystemAudioCaptureSupported);
  const [phase, setPhase] = useState<SystemRecordingPhase>('idle');
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [error, setError] = useState<SystemRecordingError | null>(null);
  const [endedExternally, setEndedExternally] = useState(false);
  const [hitDurationLimit, setHitDurationLimit] = useState(false);
  const [silent, setSilent] = useState(false);
  const [moments, setMoments] = useState<RecordingMoment[]>([]);
  const [ready, setReady] = useState<ReadyRecording | null>(null);
  const [startedAt, setStartedAt] = useState<Date | null>(null);
  const [leftover, setLeftover] = useState<RecordingSessionMeta | null>(null);

  const [courseId, setCourseId] = useState<string | null>(null);
  const [title, setTitle] = useState('');
  const [autoStartAnalysis, setAutoStartAnalysisState] = useState(readAutoStart);

  const captureRef = useRef<SystemAudioCapture | null>(null);
  const levelRef = useRef(0);
  // 録音した時間 = これまでの区間の合計 + 今の区間(録音中なら)
  const accumulatedMsRef = useRef(0);
  const segmentStartRef = useRef<number | null>(null);
  const silentSinceRef = useRef<number | null>(null);
  const phaseRef = useRef<SystemRecordingPhase>('idle');
  phaseRef.current = phase;

  const recordedMs = () =>
    accumulatedMsRef.current + (segmentStartRef.current !== null ? Date.now() - segmentStartRef.current : 0);

  const setAutoStartAnalysis = useCallback((value: boolean) => {
    setAutoStartAnalysisState(value);
    try {
      localStorage.setItem(AUTO_START_KEY, String(value));
    } catch {
      // 保存できなくても、このページを開いている間は効く
    }
  }, []);

  const resetSession = useCallback(() => {
    captureRef.current = null;
    accumulatedMsRef.current = 0;
    segmentStartRef.current = null;
    silentSinceRef.current = null;
    levelRef.current = 0;
    setElapsedSeconds(0);
    setSilent(false);
    setMoments([]);
    setReady(null);
    setStartedAt(null);
    setEndedExternally(false);
    setHitDurationLimit(false);
    setTitle('');
    setPhase('idle');
  }, []);

  const pause = useCallback(() => {
    const capture = captureRef.current;
    if (!capture || phaseRef.current !== 'recording') return;
    capture.pause();
    if (segmentStartRef.current !== null) {
      accumulatedMsRef.current += Date.now() - segmentStartRef.current;
      segmentStartRef.current = null;
    }
    levelRef.current = 0;
    silentSinceRef.current = null;
    setSilent(false);
    setElapsedSeconds(Math.floor(accumulatedMsRef.current / 1000));
    setPhase('paused');
  }, []);

  const resume = useCallback(() => {
    const capture = captureRef.current;
    if (!capture || phaseRef.current !== 'paused') return;
    if (recordedMs() >= MAX_RECORDING_SECONDS * 1000) return;
    capture.resume();
    segmentStartRef.current = Date.now();
    setPhase('recording');
  }, []);

  const finish = useCallback(async (): Promise<ReadyRecording | null> => {
    const capture = captureRef.current;
    if (!capture) return ready;
    if (phaseRef.current !== 'recording' && phaseRef.current !== 'paused') return ready;
    if (segmentStartRef.current !== null) {
      accumulatedMsRef.current += Date.now() - segmentStartRef.current;
      segmentStartRef.current = null;
    }
    setElapsedSeconds(Math.floor(accumulatedMsRef.current / 1000));
    setPhase('finishing');
    try {
      const file = await capture.stop();
      captureRef.current = null;
      const result = { file, sessionId: capture.sessionId, startedAt: capture.startedAt };
      setReady(result);
      setPhase('ready');
      return result;
    } catch {
      captureRef.current = null;
      setError('recordingFailed');
      resetSession();
      return null;
    }
  }, [ready, resetSession]);

  const start = useCallback(async (initial?: { courseId: string | null; title: string }) => {
    if (phaseRef.current !== 'idle') return;
    if (initial) {
      setCourseId(initial.courseId);
      setTitle(initial.title);
    }
    setError(null);
    setEndedExternally(false);
    setHitDurationLimit(false);
    setPhase('starting');
    try {
      const capture = await startSystemAudioCapture(() => {
        // Chromeの「共有を停止」等で共有が終わった。ここまでの録音をアップロードできる状態にする
        setEndedExternally(true);
        void finishRef.current();
      });
      captureRef.current = capture;
      markCaptureSucceeded();
      accumulatedMsRef.current = 0;
      segmentStartRef.current = Date.now();
      silentSinceRef.current = null;
      setStartedAt(capture.startedAt);
      setElapsedSeconds(0);
      setMoments([]);
      setLeftover(null);
      setPhase('recording');
    } catch (err) {
      setPhase('idle');
      if (err instanceof CaptureCancelledError) return;
      setError(
        err instanceof NoSystemAudioError
          ? 'noAudio'
          : err instanceof ScreenPermissionError
            ? 'permission'
            : 'startFailed'
      );
    }
  }, []);

  const finishRef = useRef(finish);
  finishRef.current = finish;

  const discard = useCallback(async () => {
    const capture = captureRef.current;
    const readySessionId = ready?.sessionId;
    resetSession();
    if (capture) await capture.discard();
    else if (readySessionId) await deleteRecordingSession(readySessionId).catch(() => {});
  }, [ready, resetSession]);

  const completeUpload = useCallback(async () => {
    const sessionId = ready?.sessionId;
    resetSession();
    if (sessionId) await deleteRecordingSession(sessionId).catch(() => {});
  }, [ready, resetSession]);

  // ---- リアクション/メモ(ブラウザ内のバックアップにも書く) ----
  const sessionIdForMoments = () => captureRef.current?.sessionId ?? ready?.sessionId ?? null;
  const commitMoments = (next: RecordingMoment[]) => {
    setMoments(next);
    const id = sessionIdForMoments();
    if (id) updateRecordingSessionMoments(id, next).catch(() => {});
  };
  const momentsRef = useRef(moments);
  momentsRef.current = moments;

  const addMoment = (momentType: string, noteText: string | null) => {
    if (phaseRef.current !== 'recording' && phaseRef.current !== 'paused') return;
    commitMoments([
      ...momentsRef.current,
      {
        id: crypto.randomUUID(),
        momentType,
        noteText,
        timestampSec: Math.floor(recordedMs() / 1000),
        createdAt: new Date().toISOString(),
      },
    ]);
  };
  const addReaction = (momentType: 'interesting' | 'difficult' | 'revisit') => addMoment(momentType, null);
  const addNote = (text: string) => {
    const trimmed = text.trim();
    if (trimmed) addMoment('note', trimmed);
  };
  const deleteMoment = (id: string) => commitMoments(momentsRef.current.filter((m) => m.id !== id));

  // ---- 前回の録音の復元 ----
  const refreshLeftover = useCallback(async () => {
    if (phaseRef.current !== 'idle') return;
    try {
      const sessions = await listRecordingSessions();
      setLeftover(sessions[0] ?? null);
    } catch {
      setLeftover(null);
    }
  }, []);

  const restoreLeftover = useCallback(async () => {
    if (!leftover || phaseRef.current !== 'idle') return;
    const started = new Date(leftover.startedAt);
    const file = await loadRecordingFile(leftover, systemAudioFileName(started));
    setReady({ file, sessionId: leftover.id, startedAt: started });
    setStartedAt(started);
    setMoments(leftover.moments ?? []);
    // 64kbpsで録っているので、サイズから録音した長さの目安が出る
    setElapsedSeconds(Math.round((leftover.bytes * 8) / 64_000));
    setLeftover(null);
    setPhase('ready');
  }, [leftover]);

  const discardLeftover = useCallback(async () => {
    if (!leftover) return;
    await deleteRecordingSession(leftover.id).catch(() => {});
    setLeftover(null);
  }, [leftover]);

  // ---- 経過時間・音量・無音・上限 ----
  useEffect(() => {
    if (phase !== 'recording') return;
    const timer = window.setInterval(() => {
      const capture = captureRef.current;
      if (!capture) return;
      const ms = recordedMs();
      setElapsedSeconds(Math.floor(ms / 1000));
      if (ms >= MAX_RECORDING_SECONDS * 1000) {
        setHitDurationLimit(true);
        pause();
        return;
      }
      const rms = capture.rms();
      const level = displayLevelFromRms(rms);
      levelRef.current = level;
      const now = Date.now();
      if (level === 0 || 20 * Math.log10(rms) < -50) {
        silentSinceRef.current ??= now;
        setSilent(now - silentSinceRef.current >= SILENCE_WARNING_SECONDS * 1000);
      } else {
        silentSinceRef.current = null;
        setSilent(false);
      }
    }, 100);
    return () => window.clearInterval(timer);
  }, [phase, pause]);

  // 録音中〜アップロード前は、タブを閉じる・再読み込みする前に確認を出す
  const unsaved = phase !== 'idle';
  useEffect(() => {
    if (!unsaved) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [unsaved]);

  const getLevel = useCallback(() => levelRef.current, []);

  const value = useMemo<SystemRecordingContextValue>(
    () => ({
      supported,
      phase,
      elapsedSeconds,
      error,
      endedExternally,
      hitDurationLimit,
      silent,
      moments,
      ready,
      startedAt,
      getLevel,
      courseId,
      setCourseId,
      title,
      setTitle,
      autoStartAnalysis,
      setAutoStartAnalysis,
      start,
      pause,
      resume,
      finish,
      discard,
      completeUpload,
      addReaction,
      addNote,
      deleteMoment,
      leftover,
      refreshLeftover,
      restoreLeftover,
      discardLeftover,
    }),
    // addReaction/addNote/deleteMomentはref経由で最新の値を読むので依存に入れなくてよい
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      supported,
      phase,
      elapsedSeconds,
      error,
      endedExternally,
      hitDurationLimit,
      silent,
      moments,
      ready,
      startedAt,
      getLevel,
      courseId,
      title,
      autoStartAnalysis,
      setAutoStartAnalysis,
      start,
      pause,
      resume,
      finish,
      discard,
      completeUpload,
      leftover,
      refreshLeftover,
      restoreLeftover,
      discardLeftover,
    ]
  );

  return <SystemRecordingContext.Provider value={value}>{children}</SystemRecordingContext.Provider>;
};

export function useSystemRecording(): SystemRecordingContextValue {
  const ctx = useContext(SystemRecordingContext);
  if (!ctx) throw new Error('useSystemRecording must be used within a SystemRecordingProvider');
  return ctx;
}
