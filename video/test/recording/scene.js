// Recording page in 3D — 9 seconds.
//   0.0–2.2  the phone turns into view, idle screen (gold mic)
//   2.2–3.6  the UI lifts off the glass in layers
//   3.8      the mic button is tapped: gold → red, mic → stop, pulse ring starts,
//            timer counts, waveform comes alive (3D capsules)
//   3.8–9.0  slow push-in, the phone eases back toward the camera
//
// Motion values come from the Flutter code (recording_page.dart, audio_waveform_visualizer.dart):
// AnimatedContainer 300ms color change, AnimatedSwitcher 250ms ScaleTransition for the icon,
// pulse ring 140→200pt over 1600ms with alpha (1-t)*0.5, 25 waveform bars with a sine envelope.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import * as UI from './ui.js';
import { createStage, mulberry32, gaussian, smoothstep, easeInOutSine, lerp, clamp01 } from '../../lib/stage.js';

await UI.loadFonts();

const stage = createStage({ duration: 9, fps: 30 });
const { renderer, width, height } = stage;
renderer.toneMapping = THREE.NeutralToneMapping; // keeps UI brand colors close to their sRGB values

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(30, width / height, 0.05, 200);

const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.85;

const T_TAP = 3.8;

// ---------------------------------------------------------------- units

const SCREEN_W_UNITS = 0.66; // world units; the phone is ~0.70 x 1.47
const K = SCREEN_W_UNITS / UI.SCREEN_W; // world units per pt
const ptToLocal = (x, y) => new THREE.Vector2((x - UI.SCREEN_W / 2) * K, (UI.SCREEN_H / 2 - y) * K);

function roundedRectShape(w, h, r) {
  const s = new THREE.Shape();
  const x = -w / 2;
  const y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y);
  s.absarc(x + w - r, y + r, r, -Math.PI / 2, 0, false);
  s.lineTo(x + w, y + h - r);
  s.absarc(x + w - r, y + h - r, r, 0, Math.PI / 2, false);
  s.lineTo(x + r, y + h);
  s.absarc(x + r, y + h - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(x, y + r);
  s.absarc(x + r, y + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

// ---------------------------------------------------------------- phone

const phone = new THREE.Group();
scene.add(phone);

const BEZEL = 0.016;
const PHONE_W = SCREEN_W_UNITS + BEZEL * 2 + 0.012;
const PHONE_H = UI.SCREEN_H * K + BEZEL * 2 + 0.012;
const PHONE_R = 55 * K + BEZEL + 0.006;

{
  const bevel = 0.012;
  const depth = 0.052;
  const g = new THREE.ExtrudeGeometry(roundedRectShape(PHONE_W - bevel * 2, PHONE_H - bevel * 2, PHONE_R - bevel), {
    depth,
    bevelEnabled: true,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 10,
    curveSegments: 48,
  });
  g.translate(0, 0, -(depth + bevel));
  const titanium = new THREE.MeshPhysicalMaterial({
    color: 0x5a5e66,
    metalness: 1,
    roughness: 0.3,
    clearcoat: 0.4,
    clearcoatRoughness: 0.2,
  });
  phone.add(new THREE.Mesh(g, titanium));

  // black front glass (the bezel you see around the display)
  const front = new THREE.Mesh(
    new THREE.ShapeGeometry(roundedRectShape(PHONE_W - 0.006, PHONE_H - 0.006, PHONE_R - 0.003), 48),
    new THREE.MeshPhysicalMaterial({ color: 0x030304, roughness: 0.1, metalness: 0, clearcoat: 1 }),
  );
  front.position.z = 0.0004;
  phone.add(front);
}

const screen = new THREE.Group(); // UI lives here; +z points out of the display
screen.position.z = 0.001;
phone.add(screen);

// Glass reflection: a black dielectric drawn additively adds only its specular reflection.
const glass = new THREE.Mesh(
  new THREE.ShapeGeometry(roundedRectShape(SCREEN_W_UNITS, UI.SCREEN_H * K, 55 * K), 48),
  new THREE.MeshStandardMaterial({
    color: 0x000000,
    roughness: 0.04,
    metalness: 0,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  }),
);
glass.position.z = 0.0035;
glass.renderOrder = 5;
screen.add(glass);

// ---------------------------------------------------------------- UI layers

const maxAniso = renderer.capabilities.getMaxAnisotropy();

function layerMesh(layer, { lift, order, glow = 1 }) {
  const tex = new THREE.CanvasTexture(layer.canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = maxAniso;
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false });
  mat.color.setScalar(glow); // >1 pushes the layer above the bloom threshold
  const w = layer.canvas.width / UI.PX_PER_PT;
  const h = layer.canvas.height / UI.PX_PER_PT;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w * K, h * K), mat);
  const c = ptToLocal(layer.cx, layer.cy);
  mesh.position.set(c.x, c.y, 0);
  mesh.renderOrder = order;
  screen.add(mesh);
  return { layer, mesh, tex, lift, base: c };
}

// Soft contact shadow under a lifted layer.
function shadowTexture(kind) {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  const ctx = c.getContext('2d');
  ctx.filter = 'blur(18px)';
  ctx.fillStyle = '#000';
  ctx.beginPath();
  if (kind === 'circle') ctx.arc(128, 128, 78, 0, Math.PI * 2);
  else ctx.roundRect(48, 48, 160, 160, 24);
  ctx.fill();
  const t = new THREE.CanvasTexture(c);
  return t;
}
const shadowTex = { rect: shadowTexture('rect'), circle: shadowTexture('circle') };

function addShadow(target, kind = 'rect') {
  const L = target.layer;
  const m = new THREE.Mesh(
    new THREE.PlaneGeometry(L.w * K * 1.6, L.h * K * 1.6),
    new THREE.MeshBasicMaterial({ map: shadowTex[kind], transparent: true, depthWrite: false, opacity: 0 }),
  );
  m.renderOrder = 2;
  screen.add(m);
  target.shadow = m;
}

const layers = {
  base: layerMesh(UI.base(), { lift: 0, order: 1 }),
  course: layerMesh(UI.courseCard(), { lift: 0.05, order: 10 }),
  chip: layerMesh(UI.langChip(), { lift: 0.075, order: 11 }),
  idle: layerMesh(UI.idleStatus(), { lift: 0.085, order: 12 }),
  recording: layerMesh(UI.recordingStatus(), { lift: 0.085, order: 12 }),
  timer: layerMesh(UI.timer(), { lift: 0.12, order: 13 }),
  button: layerMesh(UI.micButton(), { lift: 0.2, order: 15, glow: 1.15 }),
};
layers.base.mesh.material.alphaTest = 0.5; // rounded display corners
addShadow(layers.course);
addShadow(layers.chip);
addShadow(layers.button, 'circle');

const staticState = { seconds: 0, recordMix: 0, iconSwap: 0 };
for (const l of Object.values(layers)) l.layer.redraw(staticState);

// ---------------------------------------------------------------- waveform (3D capsules)

const WAVE_LIFT = 0.15;
const barR = (UI.WAVE.barWidth / 2) * K;
const cylGeo = new THREE.CylinderGeometry(barR, barR, 1, 32, 1, true);
const capGeo = new THREE.SphereGeometry(barR, 32, 16);
const bars = UI.WAVE.bars.map((b) => {
  const mat = new THREE.MeshStandardMaterial({
    color: 0x8e99a6,
    roughness: 0.32,
    metalness: 0.15,
    transparent: true,
    opacity: 0.25,
    emissive: 0x000000,
  });
  const g = new THREE.Group();
  const cyl = new THREE.Mesh(cylGeo, mat);
  const top = new THREE.Mesh(capGeo, mat);
  const bottom = new THREE.Mesh(capGeo, mat);
  g.add(cyl, top, bottom);
  const p = ptToLocal(b.x, UI.WAVE.centerY);
  g.position.set(p.x, p.y, barR);
  g.renderOrder = 14;
  for (const m of [cyl, top, bottom]) m.renderOrder = 14;
  screen.add(g);
  return { ...b, g, cyl, top, bottom, mat };
});

// ---------------------------------------------------------------- pulse ring + tap ripple

const ring = new THREE.Mesh(
  new THREE.TorusGeometry(1, 0.014, 24, 160),
  new THREE.MeshBasicMaterial({ color: new THREE.Color(UI.COLORS.correctionRed).multiplyScalar(1.6), transparent: true, opacity: 0, depthWrite: false }),
);
ring.renderOrder = 16;
screen.add(ring);

const ripple = new THREE.Mesh(
  new THREE.RingGeometry(0.92, 1, 96),
  new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0, depthWrite: false }),
);
ripple.renderOrder = 17;
screen.add(ripple);

// ---------------------------------------------------------------- background

{
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(60, 64, 32),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        varying vec3 vDir;
        float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
        float noise(vec3 p) {
          vec3 i = floor(p), f = fract(p);
          vec3 u = f * f * (3.0 - 2.0 * f);
          return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), u.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), u.x), u.y),
                     mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), u.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), u.x), u.y), u.z);
        }
        float fbm(vec3 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.02; a *= 0.5; } return v; }
        void main() {
          vec3 d = normalize(vDir);
          vec3 col = vec3(0.006, 0.007, 0.014);
          float n = fbm(d * 2.2 + 3.0);
          float n2 = fbm(d * 4.0 - 7.0);
          // brand nebula colors, very faint
          col += vec3(0.28, 0.12, 0.55) * pow(smoothstep(0.45, 0.85, n), 2.0) * 0.12;
          col += vec3(0.12, 0.35, 0.75) * pow(smoothstep(0.5, 0.9, n2), 2.0) * 0.08;
          gl_FragColor = vec4(col, 1.0);
        }
      `,
    }),
  );
  scene.add(sky);

  const rnd = mulberry32(9);
  const N = 6000;
  const pos = new Float32Array(N * 3);
  const col = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) {
    const v = new THREE.Vector3(gaussian(rnd), gaussian(rnd), gaussian(rnd)).normalize().multiplyScalar(50);
    pos.set([v.x, v.y, v.z], i * 3);
    const b = 0.15 + Math.pow(rnd(), 7) * 1.2;
    col.set([b, b * (0.9 + rnd() * 0.1), b * (0.85 + rnd() * 0.15)], i * 3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  const stars = new THREE.Points(g, new THREE.PointsMaterial({ size: 2.2 * (height / 1920), sizeAttenuation: false, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(stars);

  // soft glow behind the phone to separate its silhouette from the dark
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const ctx = c.getContext('2d');
  const gr = ctx.createRadialGradient(256, 256, 0, 256, 256, 256);
  gr.addColorStop(0, 'rgba(120,90,200,0.55)');
  gr.addColorStop(0.45, 'rgba(60,70,160,0.18)');
  gr.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = gr;
  ctx.fillRect(0, 0, 512, 512);
  const glowTex = new THREE.CanvasTexture(c);
  glowTex.colorSpace = THREE.SRGBColorSpace;
  const glow = new THREE.Mesh(new THREE.PlaneGeometry(4.5, 4.5), new THREE.MeshBasicMaterial({ map: glowTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  glow.position.set(0.2, 0.15, -2.2);
  scene.add(glow);
}

// rim lights for the titanium edge
const keyL = new THREE.DirectionalLight(0xfff0dd, 2.2);
keyL.position.set(-2, 2.5, 1.5);
const rimL = new THREE.DirectionalLight(0x9db8ff, 2.5);
rimL.position.set(2.5, 0.5, -1.5);
scene.add(keyL, rimL);

// ---------------------------------------------------------------- post

const rt = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples: 4 });
const composer = new EffectComposer(renderer, rt);
composer.setPixelRatio(1);
composer.setSize(width, height);
composer.addPass(new RenderPass(scene, camera));
composer.addPass(new UnrealBloomPass(new THREE.Vector2(width, height), 0.5, 0.55, 0.92));
composer.addPass(new OutputPass());
const finish = new ShaderPass({
  uniforms: { tDiffuse: { value: null }, uTime: { value: 0 }, uFade: { value: 1 }, uRes: { value: new THREE.Vector2(width, height) } },
  vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse; uniform float uTime; uniform float uFade; uniform vec2 uRes; varying vec2 vUv;
    float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 q = vUv - 0.5; q.x *= uRes.x / uRes.y;
      c.rgb *= mix(0.6, 1.0, 1.0 - smoothstep(0.25, 0.9, length(q)));
      c.rgb += (h(vUv * uRes + fract(uTime * 7.31) * 113.0) - 0.5) * 0.02;
      c.rgb *= uFade;
      gl_FragColor = c;
    }
  `,
});
composer.addPass(finish);

// ---------------------------------------------------------------- waveform signal

// Deterministic "speech" level, updated at 12 Hz like a mic amplitude stream.
const WAVE_HZ = 12;
function hash1(n) {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}
function vnoise(x) {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  return lerp(hash1(i), hash1(i + 1), u);
}
function micLevel(k) {
  const syllable = 0.55 * vnoise(k * 0.55) + 0.45 * hash1(k * 1.37);
  const phrase = smoothstep(0.25, 0.55, vnoise(k * 0.09 + 3.0));
  return clamp01(syllable * (0.25 + 0.75 * phrase) * 1.15);
}

// ---------------------------------------------------------------- timeline

const easeOutCubic = (x) => 1 - Math.pow(1 - x, 3);
const easeInOutCubic = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const seg = (t, a, b) => clamp01((t - a) / (b - a));

let lastSeconds = -1;
let lastMix = -1;
let lastSwap = -1;

function render(t) {
  finish.uniforms.uTime.value = t;
  finish.uniforms.uFade.value = smoothstep(0, 0.45, t) * (1 - smoothstep(8.5, 9.0, t));

  // --- phone pose
  const enter = easeOutCubic(seg(t, 0, 2.2));
  const tilt = easeInOutCubic(seg(t, 2.2, 3.6));
  const settle = easeInOutSine(seg(t, 3.9, 9.0));
  phone.rotation.y = lerp(-1.15, -0.42, enter) + lerp(0, -0.32, tilt) + lerp(0, 0.3, settle);
  phone.rotation.x = lerp(0.38, 0.1, enter) + lerp(0, 0.06, tilt) - lerp(0, 0.05, settle);
  phone.rotation.z = lerp(0.12, 0.0, enter);
  phone.position.set(lerp(0.12, 0, enter), lerp(-0.22, 0, enter), lerp(-0.7, 0, enter));

  // --- camera: slow push toward the button
  const push = easeInOutSine(seg(t, 3.6, 9.0));
  camera.position.set(lerp(0, 0.04, push), lerp(0.02, -0.08, push), lerp(3.75, 3.1, push));
  camera.lookAt(0, lerp(0.0, -0.06, push), 0);

  // --- explode
  const explode = easeInOutCubic(seg(t, 2.1, 3.6));
  for (const [i, l] of Object.values(layers).entries()) {
    const bob = Math.sin(t * 1.3 + i * 1.7) * 0.004 * explode;
    l.mesh.position.z = 0.002 + l.lift * explode + (l.lift ? bob : 0);
    if (l.shadow) {
      const lift = l.lift * explode;
      l.shadow.position.set(l.base.x + lift * 0.18, l.base.y - lift * 0.3, 0.0015);
      l.shadow.scale.setScalar(1 + lift * 2.5);
      l.shadow.material.opacity = 0.65 * explode;
    }
  }

  // --- tap on the mic button
  const press = t < T_TAP ? 0 : t < T_TAP + 0.12 ? seg(t, T_TAP, T_TAP + 0.12) : 1 - easeOutCubic(seg(t, T_TAP + 0.12, T_TAP + 0.4));
  const btn = layers.button;
  btn.mesh.position.z -= 0.03 * press;
  btn.mesh.scale.setScalar(1 - 0.05 * press);
  const btnZ = btn.mesh.position.z;

  const recordMix = easeInOutCubic(seg(t, T_TAP, T_TAP + 0.3)); // AnimatedContainer 300ms
  const iconSwap = seg(t, T_TAP, T_TAP + 0.25); // AnimatedSwitcher 250ms
  const seconds = Math.max(0, t - T_TAP);

  if (recordMix !== lastMix || iconSwap !== lastSwap) {
    btn.layer.redraw({ recordMix, iconSwap });
    btn.tex.needsUpdate = true;
  }
  if (Math.floor(seconds) !== lastSeconds || recordMix !== lastMix) {
    layers.timer.layer.redraw({ seconds, recordMix });
    layers.timer.tex.needsUpdate = true;
    lastSeconds = Math.floor(seconds);
  }
  lastMix = recordMix;
  lastSwap = iconSwap;

  const statusMix = smoothstep(T_TAP + 0.05, T_TAP + 0.35, t);
  layers.idle.mesh.material.opacity = 1 - statusMix;
  layers.recording.mesh.material.opacity = statusMix;
  layers.idle.mesh.visible = statusMix < 1;
  layers.recording.mesh.visible = statusMix > 0;

  // tap ripple
  const rp = seg(t, T_TAP, T_TAP + 0.55);
  const bc = ptToLocal(214, 550);
  ripple.visible = rp > 0 && rp < 1;
  ripple.position.set(bc.x, bc.y, btnZ + 0.004);
  ripple.scale.setScalar(lerp(10, 82, easeOutCubic(rp)) * K);
  ripple.material.opacity = 0.55 * (1 - rp);

  // pulse ring: 140→200pt every 1600ms, alpha (1-p)*0.5
  const recording = t >= T_TAP + 0.3;
  ring.visible = recording;
  if (recording) {
    const p = ((t - (T_TAP + 0.3)) / 1.6) % 1;
    ring.position.set(bc.x, bc.y, btnZ - 0.003);
    ring.scale.setScalar(((140 + p * 60) / 2) * K);
    ring.material.opacity = (1 - p) * 0.5 * Math.min(1, (t - T_TAP - 0.3) / 0.2 + 0.0001);
  }

  // waveform
  const waveZ = WAVE_LIFT * explode;
  const k = Math.floor(t * WAVE_HZ);
  const active = t >= T_TAP + 0.3;
  const warm = recordMix; // bars switch to the recording style with the button
  bars.forEach((b, i) => {
    let level = 0;
    if (active) {
      const kk = k - (UI.WAVE.count - 1 - i);
      if (kk / WAVE_HZ >= T_TAP + 0.3) level = Math.min(1, Math.pow(micLevel(kk), 0.6) * 1.1);
    }
    const minH = lerp(3.5, 7.0, warm);
    const hPt = minH + (UI.WAVE.height - minH) * level * b.envelope;
    const len = hPt * K;
    b.cyl.scale.y = Math.max(len, 1e-4);
    b.top.position.y = len / 2;
    b.bottom.position.y = -len / 2;
    b.g.position.z = barR + 0.002 + waveZ + Math.sin(t * 1.3 + 4 * 1.7) * 0.004 * explode;

    // colors from _WaveformPainter
    const c = new THREE.Color();
    let opacity;
    if (warm > 0 && level > 0.04) {
      c.setHSL((42 + level * 10) / 360, 0.9, 0.6, THREE.SRGBColorSpace);
      opacity = 0.5 + level * 0.5;
    } else {
      c.set(warm > 0 ? UI.COLORS.starGold : '#8E99A6');
      opacity = lerp(0.25, 0.35, warm);
    }
    b.mat.color.copy(c);
    b.mat.emissive.copy(c).multiplyScalar(warm * (0.12 + level * 0.5));
    b.mat.opacity = opacity;
  });

  composer.render();
}

stage.run(render);
