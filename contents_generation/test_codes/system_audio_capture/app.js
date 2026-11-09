'use strict';

const $ = (id) => document.getElementById(id);
const t0 = performance.now();
const events = [];

function log(msg, data) {
  const line = `[${((performance.now() - t0) / 1000).toFixed(2)}s] ${msg}`;
  events.push(data === undefined ? line : `${line} ${JSON.stringify(data)}`);
  $('log').textContent = events.join('\n');
  $('log').scrollTop = $('log').scrollHeight;
  console.log(msg, data ?? '');
}

function setStatus(text, cls) {
  $('status').textContent = text;
  $('status').className = `status ${cls || ''}`;
}

function fillTable(el, rows) {
  el.innerHTML = '';
  for (const [k, v, cls] of rows) {
    const tr = document.createElement('tr');
    const a = document.createElement('td');
    const b = document.createElement('td');
    a.textContent = k;
    b.textContent = typeof v === 'string' ? v : JSON.stringify(v);
    if (cls) b.className = cls;
    tr.append(a, b);
    el.append(tr);
  }
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function safeLabel() {
  const raw = $('label').value.trim() || 'unlabeled';
  return raw.replace(/[^A-Za-z0-9_-]+/g, '-').slice(0, 60);
}

// ---------------------------------------------------------------- environment
const MIME_CANDIDATES = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4;codecs=mp4a.40.2',
  'audio/mp4;codecs=opus',
  'audio/mp4',
  'audio/ogg;codecs=opus',
];

async function collectEnv() {
  const env = {
    userAgent: navigator.userAgent,
    secureContext: window.isSecureContext,
    hasGetDisplayMedia: !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia),
    mediaRecorder: typeof MediaRecorder !== 'undefined',
    mimeSupport: {},
  };
  if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
    try {
      const hi = await navigator.userAgentData.getHighEntropyValues(['platformVersion', 'fullVersionList']);
      env.platform = navigator.userAgentData.platform;
      env.platformVersion = hi.platformVersion;
      env.browsers = (hi.fullVersionList || []).map((b) => `${b.brand} ${b.version}`).join(', ');
    } catch (e) {
      env.uaDataError = String(e);
    }
  }
  if (env.mediaRecorder) {
    for (const m of MIME_CANDIDATES) env.mimeSupport[m] = MediaRecorder.isTypeSupported(m);
  }
  if (navigator.mediaDevices && navigator.mediaDevices.getSupportedConstraints) {
    const sc = navigator.mediaDevices.getSupportedConstraints();
    env.supportedConstraints = ['suppressLocalAudioPlayback', 'restrictOwnAudio', 'displaySurface',
      'echoCancellation', 'noiseSuppression', 'autoGainControl'].filter((k) => sc[k]);
  }
  return env;
}

let ENV = null;

async function initEnv() {
  ENV = await collectEnv();
  const supported = Object.entries(ENV.mimeSupport).filter(([, ok]) => ok).map(([m]) => m);
  fillTable($('env'), [
    ['ブラウザ', ENV.browsers || ENV.userAgent],
    ['OS', ENV.platform ? `${ENV.platform} ${ENV.platformVersion || ''}` : '(取得不可)'],
    ['Secure context', String(ENV.secureContext), ENV.secureContext ? 'ok' : 'bad'],
    ['getDisplayMedia', String(ENV.hasGetDisplayMedia), ENV.hasGetDisplayMedia ? 'ok' : 'bad'],
    ['録音できる形式', supported.join(', ') || '(なし)', supported.length ? 'ok' : 'bad'],
    ['対応 constraints', (ENV.supportedConstraints || []).join(', ')],
  ]);
  const sel = $('mime');
  sel.innerHTML = '';
  for (const m of supported) {
    const o = document.createElement('option');
    o.value = m;
    o.textContent = m;
    sel.append(o);
  }
  // Default to AAC-in-MP4 (= .m4a, what the backend stores) when the browser can record it.
  if (supported.includes('audio/mp4;codecs=mp4a.40.2')) sel.value = 'audio/mp4;codecs=mp4a.40.2';
  if (!ENV.secureContext) setStatus('http://localhost から開いてください（file:// では動きません）', 'bad');
  log('env', ENV);
}

// ---------------------------------------------------------------- test tone
let toneCtx = null;
let toneTimer = null;

function toggleTone() {
  if (toneTimer) {
    clearInterval(toneTimer);
    toneTimer = null;
    $('tone').textContent = 'テスト音 ON';
    log('test tone off');
    return;
  }
  toneCtx = toneCtx || new AudioContext();
  const beep = () => {
    const osc = toneCtx.createOscillator();
    const gain = toneCtx.createGain();
    osc.frequency.value = 440;
    gain.gain.setValueAtTime(0.0001, toneCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.2, toneCtx.currentTime + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, toneCtx.currentTime + 0.4);
    osc.connect(gain).connect(toneCtx.destination);
    osc.start();
    osc.stop(toneCtx.currentTime + 0.45);
  };
  beep();
  toneTimer = setInterval(beep, 1000);
  $('tone').textContent = 'テスト音 OFF';
  log('test tone on (440 Hz, 1 beep/s)');
}

// ---------------------------------------------------------------- capture
const REQUEST = {
  // displaySurface: 'monitor' opens Chrome's picker on the "Entire screen" pane.
  video: { displaySurface: 'monitor', frameRate: 1, width: { max: 640 }, height: { max: 360 } },
  audio: {
    echoCancellation: false,
    noiseSuppression: false,
    autoGainControl: false,
    suppressLocalAudioPlayback: false,
  },
  systemAudio: 'include',
  selfBrowserSurface: 'include',
  surfaceSwitching: 'exclude',
  monitorTypeSurfaces: 'include',
};

const S = {
  stream: null, audioTrack: null, recorder: null, chunks: [], bytes: 0,
  startedAt: 0, meterCtx: null, raf: 0, maxDb: -Infinity, frames: 0, silentFrames: 0,
  displaySurface: null, audioSettings: null, videoStoppedEarly: false, endedBy: null,
  // long-run diagnostics
  chunkCount: 0, lastDataAt: 0, maxDataGapMs: 0, heartbeats: [], hbTimer: 0,
  wakeLock: null, wakeLockStatus: 'off', hiddenMs: 0, hiddenSince: 0, timesliceMs: 1000,
};

async function acquireWakeLock() {
  if (!$('wakeLock').checked) { S.wakeLockStatus = 'off'; return; }
  try {
    S.wakeLock = await navigator.wakeLock.request('screen');
    S.wakeLockStatus = 'held';
    S.wakeLock.addEventListener('release', () => { S.wakeLockStatus = 'released'; log('wake lock released'); });
    log('wake lock acquired');
  } catch (e) {
    S.wakeLockStatus = `failed: ${e.name}`;
    log('wake lock failed', `${e.name}: ${e.message}`);
  }
}

document.addEventListener('visibilitychange', () => {
  const recording = S.recorder && S.recorder.state === 'recording';
  if (document.hidden) {
    S.hiddenSince = performance.now();
  } else if (S.hiddenSince) {
    if (recording) S.hiddenMs += performance.now() - S.hiddenSince;
    S.hiddenSince = 0;
    // the browser drops a screen wake lock when the page is hidden; take it again
    if (recording && S.wakeLockStatus !== 'held') acquireWakeLock();
  }
  if (recording) log(`visibility: ${document.visibilityState}`);
});

function heartbeat() {
  const now = performance.now();
  const hb = {
    t: Number(((now - S.startedAt) / 1000).toFixed(1)),
    bytes: S.bytes,
    chunks: S.chunkCount,
    sinceLastDataMs: Math.round(now - S.lastDataAt),
    maxDataGapMs: Math.round(S.maxDataGapMs),
    heapMB: performance.memory ? Number((performance.memory.usedJSHeapSize / 1048576).toFixed(1)) : null,
    hidden: document.hidden,
    track: S.audioTrack ? S.audioTrack.readyState : null,
    wakeLock: S.wakeLockStatus,
  };
  S.heartbeats.push(hb);
  log('heartbeat', hb);
}

function dbfs(analyser, buf) {
  analyser.getFloatTimeDomainData(buf);
  let sum = 0;
  for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
  const rms = Math.sqrt(sum / buf.length);
  return rms > 0 ? 20 * Math.log10(rms) : -Infinity;
}

function startMeter(stream) {
  S.meterCtx = new AudioContext();
  const src = S.meterCtx.createMediaStreamSource(stream); // not connected to destination: no echo
  const analyser = S.meterCtx.createAnalyser();
  analyser.fftSize = 2048;
  src.connect(analyser);
  const buf = new Float32Array(analyser.fftSize);
  const tick = () => {
    const db = dbfs(analyser, buf);
    S.frames++;
    if (db < -60) S.silentFrames++;
    if (db > S.maxDb) S.maxDb = db;
    const pct = Math.max(0, Math.min(100, ((db + 60) / 60) * 100));
    $('meterBar').style.width = `${pct}%`;
    const elapsed = (performance.now() - S.startedAt) / 1000;
    fillTable($('live'), [
      ['共有した対象', S.displaySurface || '?'],
      ['音声トラック', S.audioTrack ? `${S.audioTrack.label || '(no label)'} / ${S.audioTrack.readyState}` : 'なし'],
      ['経過', `${elapsed.toFixed(1)} s`],
      ['現在レベル', Number.isFinite(db) ? `${db.toFixed(1)} dBFS` : '無音'],
      ['最大レベル', Number.isFinite(S.maxDb) ? `${S.maxDb.toFixed(1)} dBFS` : '無音',
        S.maxDb > -50 ? 'ok' : 'warn'],
      ['録音サイズ', `${(S.bytes / 1024).toFixed(1)} KB`],
    ]);
    S.raf = requestAnimationFrame(tick);
  };
  tick();
}

async function start() {
  if (!ENV.hasGetDisplayMedia) return setStatus('このブラウザは getDisplayMedia 非対応', 'bad');
  Object.assign(S, { chunks: [], bytes: 0, maxDb: -Infinity, frames: 0, silentFrames: 0,
    videoStoppedEarly: false, endedBy: null, chunkCount: 0, maxDataGapMs: 0, heartbeats: [],
    hiddenMs: 0, hiddenSince: 0, timesliceMs: Number($('timeslice').value) });
  lastName = null;
  $('player').hidden = true;
  $('download').hidden = true;
  fillTable($('result'), []);

  let stream;
  try {
    log('getDisplayMedia request', REQUEST);
    stream = await navigator.mediaDevices.getDisplayMedia(REQUEST);
  } catch (e) {
    log('getDisplayMedia rejected', { name: e.name, message: e.message });
    return setStatus(`共有がキャンセル／拒否されました: ${e.name}`, 'bad');
  }
  S.stream = stream;
  const [video] = stream.getVideoTracks();
  const audios = stream.getAudioTracks();
  S.displaySurface = video ? video.getSettings().displaySurface : null;
  log('stream acquired', {
    displaySurface: S.displaySurface,
    videoLabel: video && video.label,
    audioTracks: audios.map((a) => ({ label: a.label, settings: a.getSettings() })),
  });

  if (!audios.length) {
    setStatus('音声トラックがありません。ダイアログで音声共有がOFFだったか、この環境では対応していません。', 'bad');
    saveJson({ outcome: 'no_audio_track' });
    stream.getTracks().forEach((t) => t.stop());
    return;
  }

  S.audioTrack = audios[0];
  S.audioSettings = S.audioTrack.getSettings();
  S.audioTrack.addEventListener('ended', () => {
    log('audio track ended');
    if (S.recorder && S.recorder.state === 'recording') { S.endedBy = 'audio_track_ended'; stop(); }
  });
  if (video) {
    video.addEventListener('ended', () => log('video track ended'));
    if ($('stopVideo').checked) {
      video.stop();
      S.videoStoppedEarly = true;
      log('video track stopped by page (audio-only test)');
    }
  }

  const audioOnly = new MediaStream([S.audioTrack]);
  const mimeType = $('mime').value;
  S.recorder = new MediaRecorder(audioOnly, mimeType ? { mimeType } : undefined);
  S.recorder.ondataavailable = (ev) => {
    const now = performance.now();
    S.maxDataGapMs = Math.max(S.maxDataGapMs, now - S.lastDataAt);
    S.lastDataAt = now;
    S.chunkCount++;
    if (ev.data && ev.data.size) { S.chunks.push(ev.data); S.bytes += ev.data.size; }
  };
  S.recorder.onstop = finish;
  S.recorder.onerror = (ev) => log('recorder error', String(ev.error || ev));
  S.recorder.start(S.timesliceMs);
  S.startedAt = performance.now();
  S.lastDataAt = S.startedAt;
  S.hbTimer = setInterval(heartbeat, 30000);
  acquireWakeLock();
  log('recording', { mimeType: S.recorder.mimeType });
  startMeter(audioOnly);

  setStatus(`録音中（${S.displaySurface}）— 音を鳴らしてメーターが動くか確認してください`, 'ok');
  $('start').disabled = true;
  $('stop').disabled = false;
}

function stop() {
  if (!S.recorder || S.recorder.state === 'inactive') return;
  S.endedBy = S.endedBy || 'user_stop';
  S.recorder.stop();
  $('stop').disabled = true;
}

async function decodeCheck(blob) {
  const ctx = new AudioContext();
  try {
    const audio = await ctx.decodeAudioData(await blob.arrayBuffer());
    let peak = 0;
    for (let c = 0; c < audio.numberOfChannels; c++) {
      const d = audio.getChannelData(c);
      for (let i = 0; i < d.length; i++) { const v = Math.abs(d[i]); if (v > peak) peak = v; }
    }
    return { ok: true, duration: audio.duration, sampleRate: audio.sampleRate,
      channels: audio.numberOfChannels, peakDbfs: peak > 0 ? 20 * Math.log10(peak) : null };
  } catch (e) {
    return { ok: false, error: `${e.name}: ${e.message}` };
  } finally {
    ctx.close();
  }
}

async function postFile(name, body, type) {
  try {
    const res = await fetch(`/save?name=${encodeURIComponent(name)}`, {
      method: 'POST', headers: { 'Content-Type': type }, body,
    });
    const json = await res.json();
    if (!res.ok) throw new Error(json.error || res.status);
    log(`saved ${name}`, json);
    return json;
  } catch (e) {
    log(`save failed for ${name} (serve.py が起動していない可能性)`, String(e));
    return null;
  }
}

let lastName = null;

async function saveJson(extra) {
  const name = `${lastName || `${stamp()}_${safeLabel()}`}.json`;
  const payload = { timestamp: new Date().toISOString(), scenario: $('label').value.trim(),
    env: ENV, request: REQUEST, ...extra, events };
  return postFile(name, JSON.stringify(payload, null, 2), 'application/json');
}

async function finish() {
  cancelAnimationFrame(S.raf);
  clearInterval(S.hbTimer);
  if (S.hiddenSince) { S.hiddenMs += performance.now() - S.hiddenSince; S.hiddenSince = 0; }
  if (S.wakeLock) { try { await S.wakeLock.release(); } catch (e) { /* already released */ } S.wakeLock = null; }
  if (S.meterCtx) S.meterCtx.close();
  const wallSec = (performance.now() - S.startedAt) / 1000;
  S.stream.getTracks().forEach((t) => t.stop());
  if (toneTimer) toggleTone();

  const mime = S.recorder.mimeType || 'audio/webm';
  const ext = mime.includes('mp4') ? 'm4a' : mime.includes('ogg') ? 'ogg' : 'webm';
  const blob = new Blob(S.chunks, { type: mime.split(';')[0] });
  lastName = `${stamp()}_${safeLabel()}`;
  const decoded = await decodeCheck(blob);
  const silentRatio = S.frames ? S.silentFrames / S.frames : null;

  const url = URL.createObjectURL(blob);
  $('player').src = url;
  $('player').hidden = false;
  $('download').href = url;
  $('download').download = `${lastName}.${ext}`;
  $('download').hidden = false;

  const audioSaved = await postFile(`${lastName}.${ext}`, blob, blob.type);
  const heard = Number.isFinite(S.maxDb) && S.maxDb > -50;
  const outcome = !decoded.ok ? 'decode_failed' : heard ? 'audio_captured' : 'silent';
  const summary = {
    outcome,
    endedBy: S.endedBy,
    displaySurface: S.displaySurface,
    audioTrackLabel: S.audioTrack.label,
    audioSettings: S.audioSettings,
    videoStoppedEarly: S.videoStoppedEarly,
    mimeType: mime,
    wallSeconds: Number(wallSec.toFixed(2)),
    bytes: blob.size,
    kbps: wallSec > 0 ? Number(((blob.size * 8) / 1000 / wallSec).toFixed(1)) : null,
    meter: { maxDbfs: Number.isFinite(S.maxDb) ? Number(S.maxDb.toFixed(1)) : null,
      silentRatio: silentRatio === null ? null : Number(silentRatio.toFixed(3)) },
    decoded,
    serverSave: audioSaved,
    longRun: {
      timesliceMs: S.timesliceMs,
      chunks: S.chunkCount,
      maxDataGapMs: Math.round(S.maxDataGapMs),
      hiddenSeconds: Number((S.hiddenMs / 1000).toFixed(1)),
      wakeLockRequested: $('wakeLock').checked,
      heartbeats: S.heartbeats,
    },
  };
  await saveJson(summary);

  const verdict = { audio_captured: ['音が録れました', 'ok'], silent: ['録音はできたが無音でした', 'warn'],
    decode_failed: ['録音ファイルを読み込めませんでした', 'bad'] }[outcome];
  setStatus(verdict[0], verdict[1]);
  fillTable($('result'), [
    ['判定', verdict[0], verdict[1]],
    ['共有した対象', S.displaySurface || '?'],
    ['形式', mime],
    ['長さ', decoded.ok ? `${decoded.duration.toFixed(1)} s（実時間 ${wallSec.toFixed(1)} s）` : decoded.error],
    ['サンプルレート / ch', decoded.ok ? `${decoded.sampleRate} Hz / ${decoded.channels}` : '-'],
    ['サイズ / ビットレート', `${(blob.size / 1024).toFixed(1)} KB / ${summary.kbps} kbps`],
    ['最大レベル', summary.meter.maxDbfs === null ? '無音' : `${summary.meter.maxDbfs} dBFS`],
    ['無音フレーム率', silentRatio === null ? '-' : `${(silentRatio * 100).toFixed(0)}%`],
    ['データ間隔の最大', `${Math.round(S.maxDataGapMs)} ms（区切り ${S.timesliceMs} ms）`,
      S.maxDataGapMs > S.timesliceMs * 3 ? 'warn' : 'ok'],
    ['裏に回っていた時間', `${(S.hiddenMs / 1000).toFixed(0)} s`],
    ['サーバー側 ffprobe の長さ', audioSaved && audioSaved.ffprobe && audioSaved.ffprobe.ok
      ? `${Number(audioSaved.ffprobe.probe.format.duration).toFixed(1)} s` : '-'],
    ['保存先', audioSaved ? audioSaved.saved : '（サーバー保存失敗。下のリンクからダウンロード）',
      audioSaved ? 'ok' : 'warn'],
  ]);
  $('start').disabled = false;
  S.recorder = null;
}

$('start').addEventListener('click', start);
$('stop').addEventListener('click', stop);
$('tone').addEventListener('click', toggleTone);
initEnv();
