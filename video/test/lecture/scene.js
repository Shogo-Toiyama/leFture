// Lecture hall test — path traced (three-gpu-pathtracer on three r187). 6 seconds.
//   Shot 1 (0–3s): close-up along the whiteboard tray — marker, cap and eraser in focus,
//                  the handwritten equations soft behind them (physical depth of field)
//   Shot 2 (3–6s): wide view from the back rows toward the boards and projector screen
//
// No people. Light comes from ceiling panels (area lights), the projector screen and
// daylight through the side windows (Poly Haven "school_hall" HDRI). Textures: Poly Haven CC0.
import * as THREE from 'three';
import { HDRLoader } from 'three/addons/loaders/HDRLoader.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import * as BufferGeometryUtils from 'three/addons/utils/BufferGeometryUtils.js';
import { WebGLPathTracer, PhysicalCamera, DenoiseMaterial } from 'three-gpu-pathtracer';
import { RectAreaLightUniformsLib } from 'three/addons/lights/RectAreaLightUniformsLib.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { createStage, mulberry32, smoothstep, easeInOutSine, lerp, clamp01 } from '../../lib/stage.js';

const params = new URLSearchParams(location.search);
// Deterministic Math.random: the path tracer builds its blue-noise texture with Math.random, so
// without this every browser session gets a different noise pattern and a resumed frame no
// longer matches its neighbours (measured: PSNR 23 dB between two sessions of the same frame).
Math.random = mulberry32(0x5eed);
const SPP = Number(params.get('spp') ?? 64); // samples per pixel per frame
// Benchmark knobs (defaults = the settings used for the first render)
const BOUNCES = Number(params.get('bounces') ?? 3); // 3 ≈ 6 visually at ~0.6x cost (results/20261108_120449_compare)
const TILES = (params.get('tiles') ?? '1x1').split('x').map(Number);
const RENDER_SCALE = Number(params.get('scale') ?? 1);
const AREA_LIGHTS = params.get('lights') !== '0';
const TEX_SIZE = Number(params.get('tex') ?? 2048);
// ?raster=1: same scene drawn with the ordinary rasterizer (no path tracing) for comparison
const RASTER = params.has('raster');

const stage = createStage({ duration: 6, fps: 30, width: Number(params.get('w') ?? 1080), height: Number(params.get('h') ?? 1920) });
const { renderer, width, height } = stage;
renderer.toneMapping = THREE.AgXToneMapping;
renderer.toneMappingExposure = 1.0;

const scene = new THREE.Scene();
const camera = new PhysicalCamera(40, width / height, 0.01, 100);

// ---------------------------------------------------------------- textures

const texLoader = new THREE.TextureLoader();
const PH = '/assets/polyhaven';
async function pbr(id, repeatX, repeatY) {
  const [map, normalMap, roughnessMap] = await Promise.all(
    ['diff', 'nor_gl', 'rough'].map((m) => texLoader.loadAsync(`${PH}/${id}/${m}.jpg`)),
  );
  map.colorSpace = THREE.SRGBColorSpace;
  for (const t of [map, normalMap, roughnessMap]) {
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeatX, repeatY);
  }
  return { map, normalMap, roughnessMap };
}

const [oak, carpet, plaster, hdr] = await Promise.all([
  pbr('oak_veneer_01', 2, 0.25),
  pbr('dirty_carpet', 6, 6),
  pbr('beige_wall_001', 4, 2),
  new HDRLoader().loadAsync(`${PH}/school_hall/school_hall_2k.hdr`),
]);
console.log('[lecture] textures loaded');
hdr.mapping = THREE.EquirectangularReflectionMapping;
scene.environment = hdr;
scene.background = hdr;
scene.environmentIntensity = 1.0;
scene.backgroundIntensity = 0.9;

// ---------------------------------------------------------------- handwriting on the boards

const BOARD_W = 4.4;
const BOARD_H = 1.32;

function boardTexture(lines, seed) {
  const c = document.createElement('canvas');
  c.width = 4096;
  c.height = Math.round((4096 * BOARD_H) / BOARD_W);
  const ctx = c.getContext('2d');
  const rnd = mulberry32(seed);
  ctx.fillStyle = '#f7f8f6';
  ctx.fillRect(0, 0, c.width, c.height);
  // faint ghosting from earlier lectures
  ctx.globalAlpha = 0.05;
  ctx.strokeStyle = '#4a5068';
  ctx.lineCap = 'round';
  for (let i = 0; i < 40; i++) {
    ctx.lineWidth = 6 + rnd() * 30;
    ctx.beginPath();
    const x = rnd() * c.width;
    const y = rnd() * c.height;
    ctx.moveTo(x, y);
    ctx.bezierCurveTo(x + rnd() * 300, y + (rnd() - 0.5) * 80, x + rnd() * 600, y + (rnd() - 0.5) * 80, x + 200 + rnd() * 700, y + (rnd() - 0.5) * 60);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  for (const l of lines) {
    if (l.draw) {
      l.draw(ctx);
      continue;
    }
    ctx.save();
    ctx.translate(l.x, l.y);
    ctx.rotate((rnd() - 0.5) * 0.025);
    ctx.font = `${l.size ?? 92}px "Marker Felt", "Chalkboard SE", sans-serif`;
    ctx.fillStyle = l.color ?? '#1c2550';
    ctx.fillText(l.text, 0, 0);
    ctx.restore();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 16;
  return t;
}

const NAVY = '#1c2550';
const BLACK = '#1d1d1f';
const RED = '#b0231c';
const GREEN = '#17663a';

const leftBoard = boardTexture(
  [
    { text: 'Lec. 14  —  Heat equation & Fourier series', x: 120, y: 150, size: 104, color: NAVY },
    { text: '∂u/∂t  =  α ∂²u/∂x² ,   0 < x < L ,  t > 0', x: 160, y: 360, color: BLACK },
    { text: 'u(0,t) = u(L,t) = 0 ,     u(x,0) = f(x)', x: 160, y: 520, color: BLACK },
    { text: 'separate:  u = X(x) T(t)   ⇒   X″/X = T′/(αT) = −λ', x: 160, y: 690, color: NAVY },
    { text: 'λₙ = (nπ/L)² ,   Xₙ = sin(nπx/L)', x: 260, y: 850, color: BLACK },
    { text: 'u(x,t) = Σ bₙ e^{−α(nπ/L)² t} sin(nπx/L)', x: 160, y: 1060, size: 100, color: RED },
    {
      draw(ctx) {
        // boxed result + a quick sketch of the first modes
        ctx.strokeStyle = RED;
        ctx.lineWidth = 7;
        ctx.strokeRect(130, 965, 2120, 140);
        ctx.strokeStyle = NAVY;
        ctx.lineWidth = 6;
        ctx.beginPath();
        ctx.moveTo(2800, 900);
        ctx.lineTo(3900, 900);
        ctx.moveTo(2820, 1150);
        ctx.lineTo(2820, 400);
        ctx.stroke();
        for (const [n, col] of [[1, NAVY], [2, GREEN], [3, RED]]) {
          ctx.strokeStyle = col;
          ctx.lineWidth = 6;
          ctx.beginPath();
          for (let i = 0; i <= 100; i++) {
            const x = 2820 + (i / 100) * 1050;
            const y = 900 - Math.sin((n * Math.PI * i) / 100) * (300 / n);
            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
          }
          ctx.stroke();
        }
        ctx.font = '80px "Marker Felt"';
        ctx.fillStyle = NAVY;
        ctx.fillText('n = 1, 2, 3', 3150, 1100);
        ctx.fillText('x', 3920, 930);
      },
    },
  ],
  11,
);

const rightBoard = boardTexture(
  [
    { text: 'bₙ = (2/L) ∫₀ᴸ f(x) sin(nπx/L) dx', x: 150, y: 190, color: BLACK },
    { text: 'orthogonality:  ∫₀ᴸ sin(mπx/L) sin(nπx/L) dx = (L/2) δₘₙ', x: 150, y: 380, color: NAVY },
    { text: 'Parseval:   (2/L)∫|f|² dx  =  Σ |bₙ|²', x: 150, y: 570, color: BLACK },
    { text: 'energy decays like  e^{−2α(π/L)² t}  →  slowest mode wins', x: 150, y: 760, color: GREEN },
    { text: 'HW 6 due Fri — Problems 3, 5, 7  (show convergence!)', x: 150, y: 1060, size: 86, color: RED },
  ],
  23,
);

function slideTexture() {
  const c = document.createElement('canvas');
  c.width = 2048;
  c.height = 1152;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#fbfbfd';
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = '#1a2a6c';
  ctx.fillRect(0, 0, c.width, 150);
  ctx.font = '600 72px "Helvetica Neue", sans-serif';
  ctx.fillStyle = '#ffffff';
  ctx.fillText('Diffusion of a Gaussian pulse', 70, 100);
  // plot
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.moveTo(120, 1000);
  ctx.lineTo(1300, 1000);
  ctx.moveTo(120, 1000);
  ctx.lineTo(120, 260);
  ctx.stroke();
  const cols = ['#d62728', '#ff7f0e', '#2ca02c', '#1f77b4'];
  [0.05, 0.12, 0.25, 0.5].forEach((s, k) => {
    ctx.strokeStyle = cols[k];
    ctx.lineWidth = 7;
    ctx.beginPath();
    for (let i = 0; i <= 200; i++) {
      const x = -1 + (i / 200) * 2;
      const y = Math.exp((-x * x) / (2 * s)) / Math.sqrt(s) * 0.22;
      const px = 120 + (i / 200) * 1180;
      const py = 1000 - y * 700;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.stroke();
  });
  ctx.font = '48px "Helvetica Neue", sans-serif';
  ctx.fillStyle = '#222';
  ['t = 0.05', 't = 0.12', 't = 0.25', 't = 0.50'].forEach((s, k) => {
    ctx.fillStyle = cols[k];
    ctx.fillText(s, 1400, 380 + k * 90);
  });
  ctx.fillStyle = '#222';
  ctx.font = '52px "Helvetica Neue", sans-serif';
  ctx.fillText('u(x,t) = (4παt)^(−1/2) exp(−x²/4αt)', 1360, 860);
  ctx.fillText('width ∝ √t', 1360, 960);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ---------------------------------------------------------------- materials

const M = {
  wall: new THREE.MeshStandardMaterial({ ...plaster, color: 0xf2efe9, roughness: 0.9 }),
  ceiling: new THREE.MeshStandardMaterial({ color: 0xe8e8e6, roughness: 0.95 }),
  carpet: new THREE.MeshStandardMaterial({ ...carpet, color: 0x6c7380, roughness: 1 }),
  stage: new THREE.MeshStandardMaterial({ ...oak, color: 0x9a8a78 }),
  deskTop: new THREE.MeshStandardMaterial({ ...oak, color: 0xffffff }),
  laminate: new THREE.MeshStandardMaterial({ color: 0x3b3e44, roughness: 0.55 }),
  fabric: new THREE.MeshStandardMaterial({ color: 0x27304a, roughness: 0.95 }),
  chairShell: new THREE.MeshStandardMaterial({ color: 0x1f2126, roughness: 0.45 }),
  aluminum: new THREE.MeshStandardMaterial({ color: 0xc8ccd2, metalness: 1, roughness: 0.32 }),
  // NOTE: MeshPhysicalMaterial clearcoat renders black in three-gpu-pathtracer 0.0.28 — use Standard
  leftBoard: new THREE.MeshStandardMaterial({ map: leftBoard, roughness: Number(params.get('boardRough') ?? 0.16) }),
  rightBoard: new THREE.MeshStandardMaterial({ map: rightBoard, roughness: Number(params.get('boardRough') ?? 0.16) }),
  screen: new THREE.MeshStandardMaterial({ color: 0x111111, emissive: 0xffffff, emissiveMap: slideTexture(), emissiveIntensity: 1.1, roughness: 0.9 }),
  // panel glow is low by default (?glow=high = old 6.0): the panel only needs to look lit; the area light under it does the lighting
  lightPanel: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xfff6e8, emissiveIntensity: params.get('glow') === 'high' ? 6 : 1.5 }), // default low (results/20261108_121618_noise)
  paper: new THREE.MeshStandardMaterial({ color: 0xf2f0ea, roughness: 0.85 }),
  markerBody: new THREE.MeshStandardMaterial({ color: 0xf4f4f2, roughness: 0.28 }),
  markerNavy: new THREE.MeshStandardMaterial({ color: 0x1b2a6b, roughness: 0.25 }),
  felt: new THREE.MeshStandardMaterial({ color: 0x1a2350, roughness: 1 }),
  eraserTop: new THREE.MeshStandardMaterial({ color: 0x15161a, roughness: 0.3 }),
  eraserFelt: new THREE.MeshStandardMaterial({ color: 0x8b8d92, roughness: 1 }),
};

function box(w, h, d, mat, x, y, z, parent = scene) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, y, z);
  parent.add(m);
  return m;
}

// ---------------------------------------------------------------- room

const ROOM_W = 16;
const ROOM_D = 18;
const CEIL = 8.2;
const ROWS = 12;
const ROW_D = 1.05;
const RISE = 0.28;
const ROW0 = 4.6;

box(ROOM_W, 0.2, ROOM_D, M.carpet, 0, -0.1, ROOM_D / 2); // floor
box(ROOM_W, 0.15, 3.2, M.stage, 0, 0.075, 1.6); // low stage in front of the boards
box(ROOM_W, 0.2, ROOM_D, M.ceiling, 0, CEIL + 0.1, ROOM_D / 2);
box(ROOM_W, CEIL, 0.2, M.wall, 0, CEIL / 2, -0.1); // front wall
box(ROOM_W, CEIL, 0.2, M.wall, 0, CEIL / 2, ROOM_D + 0.1); // back wall
box(0.2, CEIL, ROOM_D, M.wall, -ROOM_W / 2 - 0.1, CEIL / 2, ROOM_D / 2); // left wall

// right wall with three tall windows (daylight from the HDRI comes through the openings)
{
  const x = ROOM_W / 2 + 0.1;
  const winY0 = 2.6;
  const winY1 = 6.4;
  box(0.2, winY0, ROOM_D, M.wall, x, winY0 / 2, ROOM_D / 2);
  box(0.2, CEIL - winY1, ROOM_D, M.wall, x, (winY1 + CEIL) / 2, ROOM_D / 2);
  const wins = [[4.5, 6.5], [8.5, 10.5], [12.5, 14.5]];
  let z = 0;
  for (const [a, b] of wins) {
    box(0.2, winY1 - winY0, a - z, M.wall, x, (winY0 + winY1) / 2, (z + a) / 2);
    // mullion
    box(0.12, winY1 - winY0, 0.06, M.aluminum, x, (winY0 + winY1) / 2, (a + b) / 2);
    box(0.12, 0.06, b - a, M.aluminum, x, (winY0 + winY1) / 2, (a + b) / 2);
    z = b;
  }
  box(0.2, winY1 - winY0, ROOM_D - z, M.wall, x, (winY0 + winY1) / 2, (z + ROOM_D) / 2);
  // portal lights (?portal=0 to disable): an area light filling each window opening, facing into the room, so daylight
  // is sampled directly instead of being found by chance through the openings
  if (params.get('portal') !== '0') { // default on (results/20261108_121618_noise)
    for (const [a, b] of wins) {
      const l = new THREE.RectAreaLight(0xe4ecff, Number(params.get('portalI') ?? 6), b - a, winY1 - winY0);
      l.position.set(x - 0.11, (winY0 + winY1) / 2, (a + b) / 2);
      l.lookAt(0, (winY0 + winY1) / 2, (a + b) / 2);
      scene.add(l);
    }
    scene.environmentIntensity = 0.2;
  }
}

// tiered rows
const merged = { carpet: [], deskTop: [], laminate: [], fabric: [], chairShell: [], paper: [] };
const add = (key, geo, x, y, z, rx = 0, ry = 0) => {
  geo.rotateX(rx);
  geo.rotateY(ry);
  geo.translate(x, y, z);
  merged[key].push(geo);
};
const rnd = mulberry32(2024);
for (let r = 0; r < ROWS; r++) {
  const z0 = ROW0 + r * ROW_D;
  const yTop = (r + 1) * RISE;
  add('carpet', new THREE.BoxGeometry(ROOM_W, RISE, ROOM_D - z0), 0, yTop - RISE / 2, (z0 + ROOM_D) / 2);
  for (const side of [-1, 1]) {
    const xc = side * 4.0;
    const len = 5.8;
    add('deskTop', new THREE.BoxGeometry(len, 0.035, 0.46), xc, yTop + 0.74, z0 + 0.36);
    add('laminate', new THREE.BoxGeometry(len, 0.72, 0.03), xc, yTop + 0.36, z0 + 0.14);
    for (let i = 0; i < 9; i++) {
      const x = xc - len / 2 + 0.38 + i * 0.63;
      add('fabric', new THREE.BoxGeometry(0.46, 0.07, 0.42), x, yTop + 0.46, z0 + 0.84);
      add('chairShell', new THREE.BoxGeometry(0.47, 0.5, 0.04), x, yTop + 0.78, z0 + 1.03, -0.18);
      add('fabric', new THREE.BoxGeometry(0.42, 0.42, 0.03), x, yTop + 0.79, z0 + 1.0, -0.18);
      add('chairShell', new THREE.BoxGeometry(0.06, 0.42, 0.06), x, yTop + 0.21, z0 + 0.84);
      // notebooks and handouts left on some desks
      if (rnd() < 0.22) add('paper', new THREE.BoxGeometry(0.21, 0.006, 0.28), x + (rnd() - 0.5) * 0.2, yTop + 0.761, z0 + 0.36, 0, (rnd() - 0.5) * 0.6);
    }
  }
}
for (const [key, geos] of Object.entries(merged)) {
  const g = BufferGeometryUtils.mergeGeometries(geos);
  scene.add(new THREE.Mesh(g, M[key]));
}

// front: two whiteboards and the projector screen between them
const BOARD_Y = 0.92 + BOARD_H / 2 + 0.15;
function whiteboard(xc, mat) {
  const g = new THREE.Group();
  box(BOARD_W, BOARD_H, 0.015, mat, xc, BOARD_Y, 0.02, g);
  const f = 0.03;
  box(BOARD_W + f * 2, f, 0.035, M.aluminum, xc, BOARD_Y + BOARD_H / 2 + f / 2, 0.025, g);
  box(BOARD_W + f * 2, f, 0.035, M.aluminum, xc, BOARD_Y - BOARD_H / 2 - f / 2, 0.025, g);
  box(f, BOARD_H, 0.035, M.aluminum, xc - BOARD_W / 2 - f / 2, BOARD_Y, 0.025, g);
  box(f, BOARD_H, 0.035, M.aluminum, xc + BOARD_W / 2 + f / 2, BOARD_Y, 0.025, g);
  // pen tray
  const trayY = BOARD_Y - BOARD_H / 2 - f - 0.02;
  box(BOARD_W, 0.006, 0.075, M.aluminum, xc, trayY, 0.06, g);
  box(BOARD_W, 0.022, 0.005, M.aluminum, xc, trayY + 0.008, 0.098, g);
  scene.add(g);
  return trayY + 0.003;
}
const TRAY_Y = whiteboard(-5.0, M.leftBoard);
whiteboard(5.0, M.rightBoard);

box(5.4, 3.04, 0.02, M.screen, 0, 3.55, 0.06); // projected slide
box(5.6, 0.08, 0.1, M.chairShell, 0, 5.12, 0.07); // screen housing

// lectern
box(0.8, 1.1, 0.55, new THREE.MeshStandardMaterial({ ...oak, color: 0x6b5442 }), 4.0, 0.7, 2.0);

// ceiling light panels: visible emissive panel + a matching area light
const areaLights = [];
for (const x of [-4.5, 0, 4.5]) {
  for (const z of [3, 7, 11, 15]) {
    box(1.2, 0.02, 0.6, M.lightPanel, x, CEIL - 0.02, z);
    if (!AREA_LIGHTS) continue;
    const l = new THREE.RectAreaLight(0xfff4e6, 28, 1.2, 0.6);
    l.position.set(x, CEIL - 0.04, z);
    l.lookAt(x, 0, z);
    scene.add(l);
    areaLights.push(l);
  }
}

// ---------------------------------------------------------------- props on the tray

const props = new THREE.Group();
scene.add(props);

function marker() {
  const g = new THREE.Group();
  const r = 0.0095;
  const body = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.105, 48), M.markerBody);
  body.rotation.z = Math.PI / 2;
  g.add(body);
  const band = new THREE.Mesh(new THREE.CylinderGeometry(r * 1.01, r * 1.01, 0.045, 48), M.markerNavy);
  band.rotation.z = Math.PI / 2;
  band.position.x = -0.01;
  g.add(band);
  const endCap = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.96, r * 0.96, 0.012, 48), M.markerNavy);
  endCap.rotation.z = Math.PI / 2;
  endCap.position.x = -0.058;
  g.add(endCap);
  const taper = new THREE.Mesh(new THREE.CylinderGeometry(0.0045, r, 0.014, 48), M.markerBody);
  taper.rotation.z = -Math.PI / 2;
  taper.position.x = 0.0595;
  g.add(taper);
  const tip = new THREE.Mesh(new THREE.CylinderGeometry(0.0022, 0.0032, 0.01, 24), M.felt);
  tip.rotation.z = -Math.PI / 2;
  tip.position.x = 0.0715;
  g.add(tip);
  return g;
}
function markerCap() {
  const g = new THREE.Group();
  const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.0108, 0.0108, 0.042, 48), M.markerNavy);
  cap.rotation.z = Math.PI / 2;
  g.add(cap);
  const clip = new THREE.Mesh(new RoundedBoxGeometry(0.032, 0.004, 0.005, 2, 0.0015), M.markerNavy);
  clip.position.set(0.004, 0.012, 0);
  g.add(clip);
  return g;
}

const MARK_X = -5.6;
const m1 = marker();
m1.position.set(MARK_X, TRAY_Y + 0.0095, 0.065);
m1.rotation.y = 0.08;
props.add(m1);
const cap1 = markerCap();
cap1.position.set(MARK_X + 0.13, TRAY_Y + 0.0108, 0.062);
cap1.rotation.set(0.4, -0.25, 0);
props.add(cap1);
const m2 = marker();
m2.position.set(MARK_X - 0.17, TRAY_Y + 0.0095, 0.07);
m2.rotation.y = Math.PI - 0.05;
m2.children[1].material = m2.children[2].material = new THREE.MeshStandardMaterial({ color: 0xa3201c, roughness: 0.25 });
props.add(m2);

const eraser = new THREE.Group();
const eTop = new THREE.Mesh(new RoundedBoxGeometry(0.155, 0.032, 0.058, 4, 0.009), M.eraserTop);
eTop.position.y = 0.028;
const eFelt = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.014, 0.054), M.eraserFelt);
eFelt.position.y = 0.007;
eraser.add(eTop, eFelt);
eraser.position.set(MARK_X + 0.34, TRAY_Y, 0.058);
eraser.rotation.y = -0.12;
props.add(eraser);


// ---------------------------------------------------------------- rasterizer (?raster=1)
// No bounced light here, so the room gets its fill from the HDRI environment (prefiltered),
// direct light from the RectAreaLights (no shadows in the rasterizer), a shadowed sun through
// the windows, and GTAO for contact darkening in corners and under desks.
let composer = null;
function setupRaster() {
  RectAreaLightUniformsLib.init();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromEquirectangular(hdr).texture;
  scene.environmentIntensity = Number(params.get('envI') ?? 0.6);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  const sun = new THREE.DirectionalLight(0xfff0dc, Number(params.get('sunI') ?? 3));
  sun.position.set(26, 15, 6);
  sun.target.position.set(0, 0, 10);
  sun.castShadow = true;
  sun.shadow.mapSize.set(4096, 4096);
  Object.assign(sun.shadow.camera, { left: -14, right: 14, top: 14, bottom: -14, near: 1, far: 60 });
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.02;
  scene.add(sun, sun.target);
  scene.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
    }
  });
  const rt = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples: 4 });
  composer = new EffectComposer(renderer, rt);
  composer.setPixelRatio(1);
  composer.setSize(width, height);
  composer.addPass(new RenderPass(scene, camera));
  if (params.get('ao') !== '0') {
    const gtao = new GTAOPass(scene, camera, width, height);
    gtao.updateGtaoMaterial({ radius: 0.6, distanceExponent: 1.5, thickness: 1.0, scale: 1.2, samples: 16 });
    composer.addPass(gtao);
  }
  composer.addPass(new OutputPass());
}

// ---------------------------------------------------------------- partial light bake (?raster=1&bake=1)
// Planar surfaces (left whiteboard, stage floor) already carry a 0..1 UV over their front face.
// An orthographic camera sitting just above such a face sees exactly that UV square, so path
// tracing it with a white, rough material gives the light arriving at each point (radiance of
// a white Lambert surface = irradiance / π). The raster pass then shows albedo × that map with
// no live lighting on those meshes. Small props are not baked.
async function bakePlanar(targets) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const bpt = new WebGLPathTracer(renderer);
  bpt.renderDelay = 0;
  bpt.fadeDuration = 0;
  bpt.minSamples = 0;
  bpt.dynamicLowRes = false;
  bpt.rasterizeScene = false;
  bpt.renderToCanvas = false;
  bpt.bounces = BOUNCES;
  bpt.stableNoise = true;
  bpt.textureSize.set(1024, 1024);
  bpt.tiles.set(1, 1);
  const ogSize = new THREE.Vector2();
  renderer.getSize(ogSize);
  const white = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, metalness: 0 });
  const maps = [];
  for (const t of targets) {
    const og = t.mesh.material;
    t.mesh.material = white;
    renderer.setSize(t.res[0], t.res[1], false);
    bpt.setScene(scene, t.camera);
    for (let i = 0; i < 400 && (bpt.isCompiling || bpt.samples < 1); i++) { bpt.renderSample(); await sleep(20); }
    bpt.reset();
    const t0 = performance.now();
    while (bpt.samples < t.spp) {
      bpt.renderSample();
      renderer.readRenderTargetPixels(bpt.target, 0, 0, 1, 1, new Float32Array(4));
      await sleep(20);
    }
    const [w, h] = t.res;
    const raw = new Float32Array(w * h * 4);
    renderer.readRenderTargetPixels(bpt.target, 0, 0, w, h, raw);
    // light maps are smooth: a small blur evens out the remaining sample noise
    const out = new Float32Array(raw.length);
    const R = t.blur ?? 2;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let r = 0, g = 0, b = 0, n = 0;
        for (let dy = -R; dy <= R; dy++) {
          const yy = Math.min(h - 1, Math.max(0, y + dy));
          for (let dx = -R; dx <= R; dx++) {
            const xx = Math.min(w - 1, Math.max(0, x + dx));
            const i = (yy * w + xx) * 4;
            r += raw[i]; g += raw[i + 1]; b += raw[i + 2]; n++;
          }
        }
        const o = (y * w + x) * 4;
        out[o] = r / n; out[o + 1] = g / n; out[o + 2] = b / n; out[o + 3] = 1;
      }
    }
    const tex = new THREE.DataTexture(out, w, h, THREE.RGBAFormat, THREE.FloatType);
    tex.magFilter = THREE.LinearFilter;
    tex.minFilter = THREE.LinearFilter;
    tex.needsUpdate = true;
    t.mesh.material = new THREE.MeshBasicMaterial({ map: og.map ?? null, color: og.color, lightMap: tex, lightMapIntensity: Math.PI });
    maps.push({ name: t.name, ms: Math.round(performance.now() - t0), spp: t.spp, res: t.res });
    console.log(`[bake] ${t.name} ${w}x${h} ${t.spp}spp ${maps.at(-1).ms}ms`);
  }
  renderer.setSize(ogSize.x, ogSize.y, false);
  bpt.dispose();
  window.__bake = maps;
}

function findMesh(material) {
  let found = null;
  scene.traverse((o) => { if (!found && o.isMesh && o.material === material) found = o; });
  return found;
}

// ---------------------------------------------------------------- path tracer

let pt = null;
let DENOISE = true; // smart-denoise on the way to the canvas (mutable for experiments)
if (RASTER) {
  if (params.has('bake')) {
    const board = findMesh(M.leftBoard);
    const boardCam = new THREE.OrthographicCamera(-BOARD_W / 2, BOARD_W / 2, BOARD_H / 2, -BOARD_H / 2, 0.001, 20);
    boardCam.position.set(board.position.x, board.position.y, board.position.z + 0.0075 + 0.003);
    boardCam.lookAt(board.position.x, board.position.y, -5);
    const stageMesh = findMesh(M.stage);
    const stageCam = new THREE.OrthographicCamera(-ROOM_W / 2, ROOM_W / 2, 1.6, -1.6, 0.001, 20);
    stageCam.up.set(0, 0, -1); // image up = -z, matching the +y face UV of BoxGeometry
    stageCam.position.set(0, 0.15 + 0.003, 1.6);
    stageCam.lookAt(0, -5, 1.6);
    await bakePlanar([
      { name: 'left_board', mesh: board, camera: boardCam, res: [768, 230], spp: Number(params.get('bakeSpp') ?? 96) },
      { name: 'stage_floor', mesh: stageMesh, camera: stageCam, res: [1024, 205], spp: Number(params.get('bakeSpp') ?? 64) },
    ]);
  }
  setupRaster();
  console.log('[lecture] raster ready');
} else {
  console.log('[lecture] scene built');
  pt = new WebGLPathTracer(renderer);
  {
    const mat = pt._pathTracer.material; // PhysicalPathTracingMaterial
    const before = mat.fragmentShader;
    mat.fragmentShader = before.replace('uint minBounces = 3u;', 'uint minBounces = uint( RR_MIN_BOUNCES );');
    if (mat.fragmentShader === before) console.warn('[lecture] minBounces patch did not apply');
    mat.defines.RR_MIN_BOUNCES = Number(params.get('rrmin') ?? 3);
    mat.needsUpdate = true;
  }
  pt.renderDelay = 0;
  pt.fadeDuration = 0;
  pt.minSamples = 0;
  pt.dynamicLowRes = false;
  pt.rasterizeScene = false;
  pt.renderToCanvas = true;
  pt.bounces = BOUNCES;
  pt.filterGlossyFactor = 0.4;
  pt.stableNoise = !params.has('noise'); // same noise pattern every frame: grain stays put instead of boiling
  pt.textureSize.set(TEX_SIZE, TEX_SIZE);
  pt.renderScale = RENDER_SCALE;
  // Edge-aware denoise on the way to the canvas (?denoise=0 turns it off)
  DENOISE = params.get('denoise') !== '0';
  const denoiseMat = new DenoiseMaterial({ sigma: 3.0, threshold: 0.06, kSigma: 1.0 });
  pt.renderToCanvasCallback = (target, r, quad) => {
    const auto = r.autoClear;
    r.autoClear = false;
    if (DENOISE) {
      const ogMat = quad.material;
      denoiseMat.map = target.texture;
      quad.material = denoiseMat;
      quad.render(r);
      quad.material = ogMat;
    } else {
      quad.render(r);
    }
    r.autoClear = auto;
  };
  pt.tiles.set(TILES[0], TILES[1]);
  pt.setScene(scene, camera);
  // Warm-up: the path tracing shader compiles asynchronously, and samples do not advance
  // until it is done. Render until one real sample exists so frame 0 is not blank.
  while (pt.isCompiling || pt.samples < 1) {
    pt.renderSample();
    await new Promise((r) => setTimeout(r, 20));
  }
  pt.reset();
  console.log('[lecture] path tracer ready');
}


// ---------------------------------------------------------------- production denoiser
// ?denoiser=oidn (default) | smart | none. OIDN (Open Image Denoise on WebGPU) with noise-free
// albedo/normal guides drawn by the rasterizer; see RENDERING_NOTES.md (denoise experiment).
// ?auxDof=0 drops the guides on depth-of-field shots (guides are always in focus).
const DENOISER = RASTER ? 'none' : params.get('denoiser') ?? 'oidn';
let oidn = null;
const outCanvas = document.createElement('canvas');
outCanvas.width = width;
outCanvas.height = height;
const outCtx = outCanvas.getContext('2d', { willReadFrequently: true });

function grabCanvas() {
  outCtx.clearRect(0, 0, width, height);
  outCtx.drawImage(renderer.domElement, 0, 0);
  return outCtx.getImageData(0, 0, width, height);
}

function renderGuides() {
  const ogBg = scene.background;
  const ogTM = renderer.toneMapping;
  const ogCS = renderer.outputColorSpace;
  const ogExp = renderer.toneMappingExposure;
  scene.background = new THREE.Color(0, 0, 0);
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
  const pass = (make) => {
    const saved = new Map();
    scene.traverse((o) => {
      if (o.isMesh) {
        saved.set(o, o.material);
        o.material = make(o.material);
      }
    });
    renderer.setRenderTarget(null);
    renderer.render(scene, camera);
    for (const [o, m] of saved) o.material = m;
    return grabCanvas();
  };
  const albedoCache = new Map();
  const albedo = pass((m) => {
    if (!albedoCache.has(m)) albedoCache.set(m, new THREE.MeshBasicMaterial({ map: m.map ?? m.emissiveMap ?? null, color: m.map || !m.emissiveMap ? m.color : new THREE.Color(1, 1, 1) }));
    return albedoCache.get(m);
  });
  const normalMat = new THREE.MeshNormalMaterial();
  const normal = pass(() => normalMat);
  for (const m of albedoCache.values()) m.dispose();
  normalMat.dispose();
  scene.background = ogBg;
  renderer.toneMapping = ogTM;
  renderer.outputColorSpace = ogCS;
  renderer.toneMappingExposure = ogExp;
  return { albedo, normal };
}

async function setupOIDN() {
  const { initUNetFromURL } = await import('/node_modules/oidn-webgpu/dist/oidn.js');
  oidn = {
    aux: await initUNetFromURL('/assets/oidn/rt_ldr_alb_nrm.tza', undefined, { aux: true }),
    plain: await initUNetFromURL('/assets/oidn/rt_ldr.tza'),
  };
  console.log('[lecture] OIDN ready');
}

if (DENOISER === 'oidn') await setupOIDN();
DENOISE = DENOISER === 'smart'; // the library's smart-denoise filter only in 'smart' mode

function runOIDN(color, guides) {
  return new Promise((resolve, reject) => {
    (guides ? oidn.aux : oidn.plain).tileExecute({
      color,
      ...(guides ?? {}),
      done: resolve,
      error: reject,
    });
  });
}

// ---------------------------------------------------------------- timeline

const tmp = new THREE.Vector3();
function shot1(p) {
  // look down onto the tray at ~30°, sliding along it; board writing soft above
  const e = lerp(p, easeInOutSine(p), 0.5);
  camera.position.set(lerp(MARK_X + 0.34, MARK_X + 0.1, e), TRAY_Y + lerp(0.13, 0.12, e), lerp(0.46, 0.42, e));
  tmp.set(lerp(MARK_X + 0.06, MARK_X - 0.04, e), TRAY_Y + 0.09, 0.02);
  camera.lookAt(tmp);
  camera.fov = 46;
  camera.fStop = 2.0;
  camera.apertureBlades = 7;
  camera.focusDistance = camera.position.distanceTo(m1.position);
}
function shot2(p) {
  const e = lerp(p, easeInOutSine(p), 0.5);
  camera.position.set(lerp(3.2, 2.6, e), lerp(5.6, 5.3, e), lerp(17.2, 15.6, e));
  tmp.set(-0.8, 2.6, 0);
  camera.lookAt(tmp);
  camera.fov = 44;
  camera.fStop = 16;
  camera.apertureBlades = 0;
  camera.focusDistance = 15;
}

let fade = 1;
async function render(t) {
  if (t < 3) {
    shot1(t / 3);
    fade = smoothstep(0, 0.4, t) * (1 - smoothstep(2.75, 3.0, t));
  } else {
    shot2((t - 3) / 3);
    fade = smoothstep(3.0, 3.3, t) * (1 - smoothstep(5.6, 6.0, t));
  }
  if (params.get('view') === 'compare') {
    compareView();
    fade = 1;
  }
  renderer.toneMappingExposure = Math.max(fade, 0.0001);
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();
  if (RASTER) {
    const t0 = performance.now();
    composer.render();
    window.__lastFrameMs = performance.now() - t0;
    return;
  }
  pt.updateCamera();
  const started = performance.now();
  while (pt.samples < SPP) {
    pt.renderSample();
    if (pt.samples % 4 === 0) await new Promise((r) => setTimeout(r, 0));
  }
  // force the GPU to finish so the timing below is real
  renderer.readRenderTargetPixels(pt.target, 0, 0, 1, 1, new Float32Array(4));
  if (DENOISER === 'oidn') {
    pt.renderToCanvasCallback(pt.target, renderer, pt._quad); // tone-mapped path traced image
    const color = grabCanvas();
    const dof = camera.fStop < 8;
    const guides = dof && params.get('auxDof') === '0' ? null : renderGuides();
    const denoised = await runOIDN(color, guides);
    outCtx.putImageData(denoised, 0, 0);
    window.__lastFrameMs = performance.now() - started;
    return outCanvas;
  }
  window.__lastFrameMs = performance.now() - started;
  if (params.has('dbg')) {
    const px = new Float32Array(4);
    const tgt = pt.target;
    const out = [];
    for (const [fx, fy] of [[0.5, 0.5], [0.5, 0.2], [0.5, 0.8], [0.2, 0.5]]) {
      renderer.readRenderTargetPixels(tgt, Math.floor(tgt.width * fx), Math.floor(tgt.height * fy), 1, 1, px);
      out.push(Array.from(px).map((v) => v.toFixed(3)).join(','));
    }
    console.log(`[lecture] t=${t} samples=${pt.samples} ms=${window.__lastFrameMs.toFixed(0)} target=${tgt.width}x${tgt.height} type=${tgt.texture.type} px=${out.join(' | ')}`);
  }
}

// ---------------------------------------------------------------- light benchmark (?bench=1)
// One page load, small canvas (?w=270&h=480), one GPU-synced sample at a time with a short
// pause in between so the machine stays usable. Compares settings relative to each other.
async function bench() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const sync = () => renderer.readRenderTargetPixels(pt.target, 0, 0, 1, 1, new Float32Array(4));
  const settle = async () => {
    // wait for any shader recompile triggered by a setting change
    pt.reset();
    for (let i = 0; i < 400 && (pt.isCompiling || pt.samples < 1); i++) {
      pt.renderSample();
      await sleep(25);
    }
    sync();
  };
  const measure = async (shot) => {
    shot();
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
    pt.updateCamera();
    await settle();
    const times = [];
    for (let k = 0; k < 3; k++) {
      pt.reset();
      const t0 = performance.now();
      pt.renderSample();
      sync();
      times.push(performance.now() - t0);
      await sleep(60);
    }
    times.sort((a, b) => a - b);
    return Math.round(times[1] * 10) / 10; // median of 3
  };
  const variants = [
    ['base', () => {}],
    ['bounces3', () => { pt.bounces = 3; }],
    ['bounces1', () => { pt.bounces = 1; }],
    ['tiles3x3', () => { pt.tiles.set(3, 3); }],
    ['scale0.5', () => { pt.renderScale = 0.5; }],
    ['nolights', () => { for (const l of areaLights) l.visible = false; pt.updateLights(); }],
  ];
  const reset = () => {
    pt.bounces = BOUNCES;
    pt.tiles.set(TILES[0], TILES[1]);
    pt.renderScale = RENDER_SCALE;
    for (const l of areaLights) l.visible = true;
    pt.updateLights();
  };
  const out = [];
  for (const [name, apply] of variants) {
    reset();
    apply();
    const wide = await measure(() => shot2(0.5));
    const close = await measure(() => shot1(0.5));
    out.push({ name, wide_ms_per_sample: wide, close_ms_per_sample: close });
    console.log(`[bench] ${name} wide=${wide}ms close=${close}ms`);
  }
  window.__bench = { width, height, gpu: window.__stage?.gl, results: out };
}

// ---------------------------------------------------------------- bounce comparison (?compare=6,3,1)
// Looks from the stage up toward the back rows and the ceiling: the ceiling and the
// undersides only receive bounced light (the panels face down), so bounce count shows most there.
function compareView() {
  camera.position.set(-3.0, 1.6, 2.4);
  camera.lookAt(2.0, 4.6, 14.0);
  camera.fov = 62;
  camera.fStop = 16;
  camera.apertureBlades = 0;
}
async function compareBounces(list) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  compareView();
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();
  const out = {};
  const rrMat = pt._pathTracer.material;
  for (const item of list) {
    const [b, rr = 3] = String(item).split(':').map(Number);
    pt.bounces = b;
    if (rrMat.defines.RR_MIN_BOUNCES !== rr) {
      rrMat.defines.RR_MIN_BOUNCES = rr;
      rrMat.needsUpdate = true;
    }
    pt.updateCamera();
    for (let i = 0; i < 400 && pt.isCompiling; i++) { pt.renderSample(); await sleep(25); }
    pt.reset();
    const t0 = performance.now();
    while (pt.samples < SPP) {
      pt.renderSample();
      renderer.readRenderTargetPixels(pt.target, 0, 0, 1, 1, new Float32Array(4));
      await sleep(30); // keep the machine responsive
    }
    const key = `${Object.keys(out).length}_b${String(item).replace(':', '_rr')}`;
    out[key] = { ms: Math.round(performance.now() - t0), png: renderer.domElement.toDataURL('image/png') };
    console.log(`[bench] bounces=${b} rrmin=${rr} ${SPP}spp ${out[key].ms}ms`);
  }
  window.__compare = out;
}

// ---------------------------------------------------------------- denoiser experiment (?oidnExp=1)
// Compare view at a small size: ground truth (high spp) vs low-spp variants, denoised with the
// library's smart-denoise filter and with OIDN (Open Image Denoise on WebGPU), with and
// without noise-free albedo/normal guides rendered by the rasterizer.
async function oidnExperiment() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const { initUNetFromURL } = await import('/node_modules/oidn-webgpu/dist/oidn.js');
  const c2d = document.createElement('canvas');
  c2d.width = width;
  c2d.height = height;
  const ctx = c2d.getContext('2d', { willReadFrequently: true });
  const grab = () => {
    ctx.clearRect(0, 0, width, height);
    ctx.drawImage(renderer.domElement, 0, 0);
    return ctx.getImageData(0, 0, width, height);
  };
  const toURL = (img) => {
    ctx.putImageData(img, 0, 0);
    return c2d.toDataURL('image/png');
  };
  const out = { timings: {} };
  compareView();
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();

  const accumulate = async (spp) => {
    pt.updateCamera();
    const t0 = performance.now();
    while (pt.samples < spp) {
      pt.renderSample();
      renderer.readRenderTargetPixels(pt.target, 0, 0, 1, 1, new Float32Array(4));
      await sleep(25);
    }
    return Math.round(performance.now() - t0);
  };
  const present = (smart) => {
    DENOISE = smart;
    pt.renderToCanvasCallback(pt.target, renderer, pt._quad);
    return grab();
  };

  out.timings.gt96 = await accumulate(96);
  out.gt = toURL(present(false));
  console.log('[oidn] ground truth done', out.timings.gt96);

  out.timings.pt16 = await accumulate(16);
  const noisy16 = present(false);
  out.noisy16 = toURL(noisy16);
  out.smart16 = toURL(present(true));
  out.timings.pt8 = await accumulate(8);
  const noisy8 = present(false);
  out.noisy8 = toURL(noisy8);

  // noise-free guides from the rasterizer, linear output
  const ogBg = scene.background;
  const ogTM = renderer.toneMapping;
  const ogCS = renderer.outputColorSpace;
  scene.background = new THREE.Color(0, 0, 0);
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
  const swap = (make) => {
    const saved = new Map();
    scene.traverse((o) => {
      if (o.isMesh) {
        saved.set(o, o.material);
        o.material = make(o.material);
      }
    });
    renderer.setRenderTarget(null);
    renderer.render(scene, camera);
    for (const [o, m] of saved) o.material = m;
    return grab();
  };
  const albedo = swap((m) => new THREE.MeshBasicMaterial({ map: m.map ?? m.emissiveMap ?? null, color: m.map || !m.emissiveMap ? m.color : new THREE.Color(1, 1, 1) }));
  const normal = swap(() => new THREE.MeshNormalMaterial());
  scene.background = ogBg;
  renderer.toneMapping = ogTM;
  renderer.outputColorSpace = ogCS;
  out.albedo = toURL(albedo);
  out.normal = toURL(normal);

  const run = (unet, color, aux) =>
    new Promise((resolve, reject) => {
      const t0 = performance.now();
      unet.tileExecute({
        color,
        ...(aux ? { albedo, normal } : {}),
        done(img) { resolve({ img, ms: Math.round(performance.now() - t0) }); },
        error: reject,
      });
    });
  const tLoad = performance.now();
  const unetLdr = await initUNetFromURL('/assets/oidn/rt_ldr.tza');
  const unetAux = await initUNetFromURL('/assets/oidn/rt_ldr_alb_nrm.tza', undefined, { aux: true });
  out.timings.oidn_load = Math.round(performance.now() - tLoad);
  console.log('[oidn] weights loaded', out.timings.oidn_load);
  // first call compiles pipelines; time the second
  await run(unetLdr, noisy16, false);
  let r = await run(unetLdr, noisy16, false);
  out.oidn16 = toURL(r.img); out.timings.oidn_ldr = r.ms;
  await run(unetAux, noisy16, true);
  r = await run(unetAux, noisy16, true);
  out.oidnAux16 = toURL(r.img); out.timings.oidn_aux = r.ms;
  r = await run(unetAux, noisy8, true);
  out.oidnAux8 = toURL(r.img);
  console.log('[oidn] done', JSON.stringify(out.timings));
  window.__oidn = out;
}

console.log(`spp=${SPP}`);
stage.run(render);
if (params.has('oidnExp')) oidnExperiment().catch((e) => { console.error('[oidn] failed', e?.message ?? e); window.__oidn = { error: String(e?.message ?? e) }; });
if (params.has('bench')) bench();
if (params.has('compare')) compareBounces(params.get('compare').split(','));
