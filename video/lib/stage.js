// Browser-side harness shared by every scene.
//
// A scene supplies render(t) where t is seconds on the timeline. Nothing in a scene
// may read wall-clock time: every frame is a pure function of t, so the capture
// script can render frame i at t = i / fps and get the same picture every run,
// no matter how long the frame took to draw.
//
// Preview: open the page normally; it plays in real time and loops.
//   keys: space = pause, ←/→ = step one frame, digits 0-9 = jump to 0%..90%
//   ?t=2.5 opens paused at that time.
// Capture: ?capture=1 — the page only draws when the capture script calls renderAt(t).
import * as THREE from 'three';

export function createStage({ width = 1080, height = 1920, fps = 30, duration }) {
  const params = new URLSearchParams(location.search);
  const capture = params.has('capture');

  const renderer = new THREE.WebGLRenderer({
    antialias: false, // the composer's multisampled target does the AA
    alpha: false, // opaque canvas: custom blend factors also hit alpha, and a transparent pixel reads as white in a PNG
    preserveDrawingBuffer: true, // lets toDataURL read the frame after render
    powerPreference: 'high-performance',
  });
  renderer.setPixelRatio(1);
  renderer.setSize(width, height, false);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  document.body.appendChild(renderer.domElement);

  const style = document.createElement('style');
  style.textContent = `
    html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
    canvas { position: absolute; inset: 0; margin: auto; max-width: 100vw; max-height: 100vh;
             width: auto !important; height: 100vh !important; aspect-ratio: ${width} / ${height}; }
    #hud { position: fixed; left: 8px; bottom: 8px; color: #fff8; font: 12px ui-monospace, monospace; }
  `;
  document.head.appendChild(style);

  const frames = Math.round(duration * fps);

  function run(render) {
    window.__stage = {
      width,
      height,
      fps,
      duration,
      frames,
      gl: (() => {
        const gl = renderer.getContext();
        const ext = gl.getExtension('WEBGL_debug_renderer_info');
        return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      })(),
      // render may return a Promise (path tracing accumulates samples asynchronously)
      // and may return its own finished canvas (e.g. after a denoiser) to be captured instead
      async renderAt(t) {
        const out = await render(t);
        const canvas = out instanceof HTMLCanvasElement ? out : renderer.domElement;
        return canvas.toDataURL('image/png');
      },
    };
    window.__ready = true;
    if (capture) return;

    const hud = document.createElement('div');
    hud.id = 'hud';
    document.body.appendChild(hud);

    let t = params.has('t') ? Number(params.get('t')) : 0;
    let paused = params.has('t');
    let last = performance.now();
    addEventListener('keydown', (e) => {
      if (e.code === 'Space') paused = !paused;
      if (e.code === 'ArrowRight') { paused = true; t = Math.min(duration, t + 1 / fps); }
      if (e.code === 'ArrowLeft') { paused = true; t = Math.max(0, t - 1 / fps); }
      if (/^Digit\d$/.test(e.code)) t = (Number(e.code.slice(5)) / 10) * duration;
    });
    let busy = false;
    renderer.setAnimationLoop(async (now) => {
      if (busy) return;
      const dt = (now - last) / 1000;
      last = now;
      if (!paused) t = (t + dt) % duration;
      busy = true;
      await render(t);
      busy = false;
      hud.textContent = `${t.toFixed(2)}s / ${duration}s  frame ${Math.round(t * fps)}${paused ? '  (paused)' : ''}`;
    });
  }

  return { renderer, width, height, fps, duration, frames, capture, run };
}

// ---------- small helpers every scene uses ----------

/** Deterministic PRNG so every run builds the identical scene. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function gaussian(rnd) {
  const u1 = Math.max(rnd(), 1e-9);
  const u2 = rnd();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

export const clamp01 = (x) => Math.min(1, Math.max(0, x));
export const smoothstep = (a, b, x) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
export const easeInOutSine = (x) => -(Math.cos(Math.PI * x) - 1) / 2;
export const lerp = (a, b, t) => a + (b - a) * t;
