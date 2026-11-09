/**
 * 「PCが鳴らしている音」(Zoomアプリ・ブラウザの動画など)をそのまま録音する。
 *
 * getDisplayMedia()の画面共有ダイアログで「画面全体」+「システム音声を共有」を
 * 選んでもらい、その音声トラックだけをMediaRecorderでm4a(AAC)に録る。
 * イヤホン/Bluetoothイヤホンで聞いていても、出力デバイスに送られる前の音を取るので録れる。
 *
 * 設定値は contents_generation/test_codes/system_audio_capture/ の実機検証
 * (macOS 27.2 + Chrome 156、2026-11-07〜08)で確認したもの:
 * - 'audio/mp4;codecs=mp4a.40.2' で録る。webmはffprobeの長さがN/Aになり、
 *   バックエンドの音声長取得(helpers._get_audio_duration_seconds)が失敗する。
 *   m4a(断片化MP4)はffmpeg 4.4〜9.0のすべてで長さ取得・区間切り出しが通った。
 * - 映像トラックは開始直後に止めてよい(60分録音で音声は最後まで途切れなかった)。
 * - 64kbpsを明示する。未指定だと約123kbps(60分で57MB)になる。
 * - 10秒区切り。タブが裏に回るとデータの届く間隔が最大20秒に延びるが、欠落はしない。
 * - pause()/resume()で一時停止しても1本のm4aになり、止めていた時間はファイルから抜ける
 *   (6秒録音→6秒停止→6秒録音で12秒のファイル。ffprobe 4.4〜7.1で確認)。
 * - 「システム音声を共有」トグルは初期状態OFFで、ページ側からONにはできない。
 *   そのため共有直後に音声トラックの有無を確かめ、無ければNoSystemAudioErrorにする。
 */

import { appendRecordingChunk, createRecordingSession, deleteRecordingSession } from './recordingStore';

export const SYSTEM_AUDIO_MIME_TYPE = 'audio/mp4;codecs=mp4a.40.2';
const AUDIO_BITS_PER_SECOND = 64_000;
const TIMESLICE_MS = 10_000;

interface UADataLike {
  brands?: { brand: string }[];
  mobile?: boolean;
}

/**
 * システム音声の録音が使える見込みのある環境か。
 * SafariとFirefoxはgetDisplayMediaで音声を返さないため、Chromium系(Chrome/Edge)の
 * デスクトップ版に限る。macOSは14.2未満だとシステム音声の選択肢が出ないが、
 * これは事前に判定できないので、共有後の音声トラックの有無で判断する。
 */
export function isSystemAudioCaptureSupported(): boolean {
  if (typeof navigator === 'undefined' || typeof window === 'undefined') return false;
  const uaData = (navigator as Navigator & { userAgentData?: UADataLike }).userAgentData;
  const isChromium = !!uaData?.brands?.some((b) => b.brand === 'Chromium');
  return (
    isChromium &&
    !uaData?.mobile &&
    !!navigator.mediaDevices?.getDisplayMedia &&
    typeof MediaRecorder !== 'undefined' &&
    MediaRecorder.isTypeSupported(SYSTEM_AUDIO_MIME_TYPE)
  );
}

/** 共有はされたが音声が付いていなかった(トグルがOFFのまま、または非対応のOS)。 */
export class NoSystemAudioError extends Error {
  constructor() {
    super('No audio was shared');
    this.name = 'NoSystemAudioError';
  }
}

/** ユーザーが共有ダイアログを閉じた。エラー表示は不要。 */
export class CaptureCancelledError extends Error {
  constructor() {
    super('Screen sharing was cancelled');
    this.name = 'CaptureCancelledError';
  }
}

/**
 * macOSの「画面収録」でChromeが許可されていない。Chromeはこのとき
 * NotAllowedError("Permission denied by system")を返す(ユーザーが閉じた場合は "by user")。
 */
export class ScreenPermissionError extends Error {
  constructor() {
    super('Screen recording permission is blocked by the system');
    this.name = 'ScreenPermissionError';
  }
}

export interface SystemAudioCapture {
  readonly sessionId: string;
  readonly startedAt: Date;
  /** 現在の音量のRMS(0〜1)。0は無音。 */
  rms(): number;
  /** 録音を一時停止する。一時停止中の音はファイルに入らない(止めていた時間はファイルから抜ける)。 */
  pause(): void;
  resume(): void;
  /** 録音を止め、ここまでの音声をFileとして返す。 */
  stop(): Promise<File>;
  /** 録音を止めて捨てる。ブラウザ内のバックアップも消す。 */
  discard(): Promise<void>;
  /** 録音を止める。バックアップは残す(画面が消えたとき用。次回復元できる)。 */
  abort(): void;
}

export function systemAudioFileName(startedAt: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  const d = startedAt;
  return `lefture-recording-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}.m4a`;
}

/**
 * 共有ダイアログを開き、録音を始める。必ずユーザー操作(クリック)の中から呼ぶこと。
 * onEnded: Chromeの「共有を停止」ボタンなど、ページ外で共有が終わったときに呼ばれる。
 */
export async function startSystemAudioCapture(onEnded: () => void): Promise<SystemAudioCapture> {
  // Chrome固有のオプション(systemAudio等)は標準の型定義に無いので広げて渡す
  const options: DisplayMediaStreamOptions & Record<string, unknown> = {
    // 'monitor'で共有ダイアログが「画面全体」のタブで開く
    video: { displaySurface: 'monitor', frameRate: 1, width: { max: 640 }, height: { max: 360 } },
    audio: {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      suppressLocalAudioPlayback: false,
    } as MediaTrackConstraints,
    systemAudio: 'include',
    selfBrowserSurface: 'exclude',
    surfaceSwitching: 'exclude',
    monitorTypeSurfaces: 'include',
  };

  let stream: MediaStream;
  try {
    stream = await navigator.mediaDevices.getDisplayMedia(options);
  } catch (err) {
    if (err instanceof DOMException && err.name === 'NotAllowedError') {
      throw /system/i.test(err.message) ? new ScreenPermissionError() : new CaptureCancelledError();
    }
    throw err;
  }

  const [audioTrack] = stream.getAudioTracks();
  if (!audioTrack) {
    stream.getTracks().forEach((t) => t.stop());
    throw new NoSystemAudioError();
  }
  // 画面の映像は使わないので止める(Chromeの共有自体は音声トラックで続く)
  stream.getVideoTracks().forEach((t) => t.stop());

  const audioStream = new MediaStream([audioTrack]);
  const recorder = new MediaRecorder(audioStream, {
    mimeType: SYSTEM_AUDIO_MIME_TYPE,
    audioBitsPerSecond: AUDIO_BITS_PER_SECOND,
  });

  const sessionId = crypto.randomUUID();
  const startedAt = new Date();
  const chunks: Blob[] = [];
  let seq = 0;
  let storeOk = true;
  // セッション行の作成が終わる前に最初のチャンクを書かないよう、書き込みを直列化する
  let storeQueue: Promise<void> = createRecordingSession(sessionId, startedAt, SYSTEM_AUDIO_MIME_TYPE).catch(
    (err) => {
      storeOk = false;
      console.warn('[systemAudio] recording backup unavailable', err);
    }
  );

  recorder.ondataavailable = (ev) => {
    if (!ev.data || ev.data.size === 0) return;
    chunks.push(ev.data);
    const n = seq++;
    const blob = ev.data;
    storeQueue = storeQueue.then(() => {
      if (!storeOk) return;
      return appendRecordingChunk(sessionId, n, blob).catch((err) => {
        console.warn('[systemAudio] failed to back up chunk', n, err);
      });
    });
  };

  // 'stop'イベントは、最後のdataavailableの後に届く。録音側が先に止まった場合
  // (共有停止で音声トラックが終わった等)でも、これを待てば最後のチャンクを取りこぼさない
  let recorderFailed = false;
  const stopped = new Promise<void>((resolve) => {
    recorder.addEventListener('stop', () => resolve(), { once: true });
  });
  recorder.addEventListener('error', (ev) => {
    recorderFailed = true;
    console.warn('[systemAudio] recorder error', ev);
  });

  // 音量メーター(スピーカーには繋がないので二重に聞こえることはない)
  const audioCtx = new AudioContext();
  const analyser = audioCtx.createAnalyser();
  analyser.fftSize = 2048;
  audioCtx.createMediaStreamSource(audioStream).connect(analyser);
  const buf = new Float32Array(analyser.fftSize);

  let finished = false;
  const cleanup = () => {
    audioTrack.removeEventListener('ended', handleEnded);
    audioTrack.stop();
    audioCtx.close().catch(() => {});
  };
  function handleEnded() {
    if (!finished) onEnded();
  }
  audioTrack.addEventListener('ended', handleEnded);

  recorder.start(TIMESLICE_MS);

  return {
    sessionId,
    startedAt,
    rms() {
      analyser.getFloatTimeDomainData(buf);
      let sum = 0;
      for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
      return Math.sqrt(sum / buf.length);
    },
    pause() {
      if (recorder.state === 'recording') recorder.pause();
    },
    resume() {
      if (recorder.state === 'paused') recorder.resume();
    },
    async stop() {
      finished = true;
      if (recorder.state !== 'inactive') recorder.stop();
      await stopped;
      cleanup();
      // 最後のチャンクのバックアップ完了を待ってから返す
      await storeQueue;
      if (chunks.length === 0) throw new Error(recorderFailed ? 'Recording failed' : 'Nothing was recorded');
      return new File(chunks, systemAudioFileName(startedAt), { type: 'audio/mp4' });
    },
    async discard() {
      finished = true;
      // これ以降に届くチャンクはバックアップしない(キュー上の書き込みも実行時にスキップされる)
      storeOk = false;
      if (recorder.state !== 'inactive') recorder.stop();
      cleanup();
      await storeQueue;
      await deleteRecordingSession(sessionId).catch(() => {});
    },
    abort() {
      finished = true;
      if (recorder.state !== 'inactive') recorder.stop();
      cleanup();
    },
  };
}

/**
 * Flutter版(recording_controller.dart の _calculatePcmAudioLevel)と同じ音量の数値(0〜1)。
 * 講義の声に自然に反応するよう、RMSの平方根を持ち上げている。
 */
export function displayLevelFromRms(rms: number): number {
  if (rms <= 0.0003) return 0;
  return Math.min(1, Math.sqrt(rms) * 2.8);
}

// ---- 初回のMac設定の案内用 ----
// ページからはmacOSの「画面収録」の許可状態を事前に知る方法が無い
// (navigator.permissions.query({name:'display-capture'})は許可済みのMacでも"prompt"を返す。
// contents_generation/test_codes/system_audio_capture/permission_probe.html で確認)。
// そこで「このブラウザで一度も録音に成功していないMac」には、先に設定の案内を出す。
const CAPTURE_SUCCEEDED_KEY = 'lefture.systemAudio.succeededOnce';

export function isMacPlatform(): boolean {
  const uaData = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData;
  if (uaData?.platform) return uaData.platform === 'macOS';
  return /Mac OS X/.test(navigator.userAgent);
}

export function hasCaptureSucceededBefore(): boolean {
  try {
    return localStorage.getItem(CAPTURE_SUCCEEDED_KEY) === '1';
  } catch {
    return false;
  }
}

export function markCaptureSucceeded(): void {
  try {
    localStorage.setItem(CAPTURE_SUCCEEDED_KEY, '1');
  } catch {
    // 保存できなければ、次回も案内が出るだけ
  }
}
