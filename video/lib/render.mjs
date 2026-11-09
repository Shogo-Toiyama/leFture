// Render a scene to an mp4, one deterministic frame at a time.
//
//   node lib/render.mjs test/galaxy [--fps 30] [--from 0] [--to <seconds>] [--stills 0,1.5,3]
//   node lib/render.mjs test/lecture --query spp=8 --resume test/lecture/out/frames/<run>   (continue a stopped run)
//
// Output: <scene>/out/<YYYYMMDD_HHMMSS>_<name>.mp4 plus a .json run report
// (GPU string, frame count, render time). --stills also saves PNGs of single
// frames for review without rendering the whole clip.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const args = process.argv.slice(2);
const sceneDir = args[0];
if (!sceneDir) {
  console.error('usage: node lib/render.mjs <scene dir> [--fps n] [--from s] [--to s] [--stills a,b,c]');
  process.exit(1);
}
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '_').slice(0, 15);
const name = path.basename(sceneDir);
const outDir = path.join(sceneDir, 'out');
fs.mkdirSync(outDir, { recursive: true });

const server = await startServer(0);
const extra = opt('query', '');
const url = `http://127.0.0.1:${server.address().port}/${sceneDir}/?capture=1${extra ? '&' + extra : ''}`;

let browser;
let page;
// (Re)launch Chrome and load the scene. Long path-traced renders can lose the tab,
// so the frame loop relaunches and retries the same frame (frames are deterministic).
async function launch() {
  if (browser) await browser.close().catch(() => {});
  browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    protocolTimeout: 0, // path-traced frames can take minutes
    args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu', '--enable-unsafe-webgpu', '--no-first-run'],
  });
  page = await browser.newPage();
  page.on('console', (m) => { if (!/deprecated/.test(m.text())) console.log('[page]', m.text()); });
  page.on('pageerror', (e) => console.error('[page error]', e.message));
  await page.goto(url);
  await page.waitForFunction('window.__ready === true', { timeout: 600000 });
}
await launch();

const info = await page.evaluate(() => {
  const s = window.__stage;
  return { width: s.width, height: s.height, fps: s.fps, duration: s.duration, frames: s.frames, gl: s.gl };
});
console.log(`GPU: ${info.gl}`);
console.log(`${info.width}x${info.height} @ ${info.fps}fps, ${info.duration}s`);

const grab = async (t) => {
  const dataUrl = await page.evaluate((tt) => window.__stage.renderAt(tt), t);
  return Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64');
};

const stills = opt('stills');
if (stills) {
  for (const t of stills.split(',').map(Number)) {
    const tag = opt('query', '').replace(/[^a-z0-9]+/gi, '-');
    const file = path.join(outDir, `${stamp}_${name}_t${t.toFixed(2)}${tag ? '_' + tag : ''}.png`);
    const s0 = Date.now();
    fs.writeFileSync(file, await grab(t));
    console.log(`still → ${file}  (${((Date.now() - s0) / 1000).toFixed(1)}s)`);
  }
  await browser.close();
  server.close();
  process.exit(0);
}

// Frames are written one PNG per frame to a frames folder, then joined by ffmpeg.
// --resume <frames dir> skips frames already on disk, so a long render can be stopped
// (Ctrl+C) and continued later with the same settings (read back from meta.json).
const resumeDir = opt('resume');
let meta;
const framesDir = resumeDir ?? path.join(outDir, 'frames', `${stamp}_${name}`);
fs.mkdirSync(framesDir, { recursive: true });
const metaFile = path.join(framesDir, 'meta.json');
if (resumeDir && fs.existsSync(metaFile)) {
  meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
  if ((meta.query ?? '') !== extra) {
    console.error(`[render] --resume: query differs from the original run ("${meta.query}" vs "${extra}"). Pass the same --query.`);
    process.exit(1);
  }
} else {
  meta = {
    scene: sceneDir,
    query: extra,
    fps: Number(opt('fps', info.fps)),
    from: Number(opt('from', 0)),
    to: Number(opt('to', info.duration)),
    started_at: new Date().toISOString(),
  };
  fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
}
const { fps, from, to } = meta;
if (![fps, from, to].every(Number.isFinite) || to <= from) {
  console.error(`[render] bad --fps/--from/--to: fps=${fps} from=${from} to=${to}`);
  process.exit(1);
}
const first = Math.round(from * fps);
const total = Math.round((to - from) * fps);
const frameFile = (i) => path.join(framesDir, `f_${String(first + i).padStart(5, '0')}.png`);

const started = Date.now();
let relaunches = 0;
let rendered = 0;
for (let i = 0; i < total; i++) {
  if (fs.existsSync(frameFile(i))) continue;
  let png;
  for (let attempt = 0; ; attempt++) {
    try {
      png = await grab(from + i / fps);
      break;
    } catch (e) {
      if (attempt >= 3) throw e;
      relaunches++;
      console.error(`\n[render] frame ${i} failed (${e.message.split('\n')[0]}); relaunching Chrome (attempt ${attempt + 1})`);
      await launch();
    }
  }
  fs.writeFileSync(frameFile(i) + '.tmp', png);
  fs.renameSync(frameFile(i) + '.tmp', frameFile(i)); // never leave a half-written frame
  rendered++;
  const el = (Date.now() - started) / 1000;
  const per = el / rendered;
  const done = fs.readdirSync(framesDir).filter((f) => f.endsWith('.png')).length;
  const eta = Math.round(per * (total - done));
  fs.writeFileSync(path.join(framesDir, 'progress.json'), JSON.stringify({ done, total, sec_per_frame: Number(per.toFixed(2)), eta_seconds: eta, relaunches }, null, 2));
  console.log(`frame ${done}/${total}  ${per.toFixed(1)} s/frame  ETA ${Math.floor(eta / 60)}m${String(eta % 60).padStart(2, '0')}s`);
}

const outFile = path.join(outDir, `${path.basename(framesDir)}.mp4`);
await new Promise((resolve, reject) => {
  const ff = spawn('ffmpeg', [
    '-y', '-loglevel', 'error',
    '-framerate', String(fps), '-start_number', String(first), '-i', path.join(framesDir, 'f_%05d.png'),
    '-frames:v', String(total),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', outFile,
  ], { stdio: ['ignore', 'inherit', 'inherit'] });
  ff.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`))));
});
const seconds = (Date.now() - started) / 1000;
console.log(`→ ${outFile}`);

fs.writeFileSync(
  outFile.replace(/\.mp4$/, '.json'),
  JSON.stringify(
    {
      scene: sceneDir,
      file: path.basename(outFile),
      frames_dir: framesDir,
      gpu: info.gl,
      resolution: `${info.width}x${info.height}`,
      fps,
      from,
      to,
      frames: total,
      rendered_this_run: rendered,
      relaunches,
      query: extra || undefined,
      render_seconds_this_run: Number(seconds.toFixed(1)),
      sec_per_frame: rendered ? Number((seconds / rendered).toFixed(2)) : null,
      bytes: fs.statSync(outFile).size,
    },
    null,
    2,
  ),
);

await browser.close();
server.close();
