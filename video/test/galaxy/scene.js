// Galaxy test — two 3-second shots.
//   Shot 1 (0–3s): high wide view, slow push-in while the disk turns.
//   Shot 2 (3–6s): grazing pass low over the outer disk, looking toward the core.
//
// Structure follows the app's galaxy (webapp/src/components/GalaxyView.tsx):
// 3 logarithmic arms, spiral tightness 5.0, inner hole 0.14 R, the same star and
// nebula palettes. On top of that, for realism: ~400k stars, differential rotation,
// dust lanes on the inner edge of each arm, pink star-forming knots, wispy gas.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { createStage, mulberry32, gaussian, smoothstep, easeInOutSine, lerp } from '../../lib/stage.js';

const stage = createStage({ duration: 6, fps: 30 });
const { renderer, width, height } = stage;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x05060b);

const FOV = 50;
const camera = new THREE.PerspectiveCamera(FOV, width / height, 0.05, 3000);
const projScale = height / (2 * Math.tan(THREE.MathUtils.degToRad(FOV) / 2));

// ---------------------------------------------------------------- galaxy model

const R = 10; // galaxy radius in world units
const ARMS = 3;
const TIGHT = 5.0;
const MIN_R = 0.14 * R;

// Brand palettes from the app (GalaxyView.tsx)
const C = (hex) => new THREE.Color(hex); // hex → linear working space
const STAR_WHITE = C('#FFFFFF');
const STAR_BLUE = C('#B7D8FF');
const STAR_WARM = C('#FFE7B0');
const STAR_PINK = C('#FFB7B7');
const NEB_PINK = C('#FF5FA2');
const NEB_ORANGE = C('#FF9A3D');
const NEB_PURPLE = C('#B86BFF');
const NEB_BLUE = C('#4FA8FF');
const CORE_WARM = C('#FFC27A');

const armAngle = (r, arm) => TIGHT * Math.log(Math.max(r / MIN_R, 1e-4)) + (arm * 2 * Math.PI) / ARMS;

function buildStars() {
  const rnd = mulberry32(42);
  const pos = [];
  const col = [];
  const size = [];
  const phase = [];
  const tmp = new THREE.Color();
  const push = (x, y, z, color, gain, s) => {
    pos.push(x, y, z);
    col.push(color.r * gain, color.g * gain, color.b * gain);
    size.push(s);
    phase.push(rnd() * Math.PI * 2);
  };

  // Bulge: squashed ball of old, warm stars
  for (let i = 0; i < 90000; i++) {
    const s = Math.pow(rnd(), 0.6);
    const x = gaussian(rnd) * 1.25 * s;
    const y = gaussian(rnd) * 0.7 * s;
    const z = gaussian(rnd) * 1.25 * s;
    tmp.copy(STAR_WARM).lerp(CORE_WARM, rnd() * 0.6);
    push(x, y, z, tmp, 0.35 + rnd() * 0.45, 0.025 + rnd() * 0.03);
  }

  // Arm stars: young, blue-white, concentrated on the log spirals
  for (let i = 0; i < 200000; i++) {
    const u = Math.pow(rnd(), 1.25);
    const r = MIN_R + u * (R - MIN_R);
    const rn = r / R;
    const arm = Math.floor(rnd() * ARMS);
    const theta = armAngle(r, arm) + gaussian(rnd) * (0.08 + rn * 0.12);
    const rw = r + gaussian(rnd) * 0.25 * rn;
    const y = gaussian(rnd) * 0.14 * (1 - 0.55 * rn);
    const p = rnd();
    const color = p < 0.5 ? STAR_BLUE : p < 0.82 ? STAR_WHITE : p < 0.95 ? STAR_WARM : STAR_PINK;
    let gain = (0.3 + rnd() * 0.5) * (1.15 - 0.55 * rn);
    let s = 0.018 + rnd() * 0.028;
    if (rnd() < 0.006) {
      gain *= 4.5; // a few very bright giants for the bloom to catch
      s *= 2.4;
    }
    push(rw * Math.cos(theta), y, rw * Math.sin(theta), color, gain, s);
  }

  // Inter-arm disk: exponential, dimmer and warmer
  for (let i = 0; i < 110000; i++) {
    const r = Math.min(R * 1.2, -Math.log(1 - rnd() * 0.97) * 3.0 + 0.6);
    const theta = rnd() * Math.PI * 2;
    const y = gaussian(rnd) * 0.18 * (1 - 0.5 * (r / R));
    tmp.copy(STAR_WHITE).lerp(STAR_WARM, rnd());
    push(r * Math.cos(theta), y, r * Math.sin(theta), tmp, 0.18 + rnd() * 0.25, 0.018 + rnd() * 0.02);
  }

  // Star-forming knots: tight pink/blue clusters strung along the arms
  const knots = [];
  for (let k = 0; k < 420; k++) {
    const r = MIN_R * 1.6 + Math.pow(rnd(), 0.9) * (R * 0.95 - MIN_R * 1.6);
    const arm = Math.floor(rnd() * ARMS);
    const theta = armAngle(r, arm) + gaussian(rnd) * 0.06;
    const cx = r * Math.cos(theta);
    const cz = r * Math.sin(theta);
    const cy = gaussian(rnd) * 0.05;
    knots.push([cx, cy, cz]);
    const n = 18 + Math.floor(rnd() * 26);
    for (let j = 0; j < n; j++) {
      const c = rnd() < 0.6 ? STAR_PINK : STAR_BLUE;
      push(cx + gaussian(rnd) * 0.11, cy + gaussian(rnd) * 0.05, cz + gaussian(rnd) * 0.11, c, 0.6 + rnd() * 0.7, 0.022 + rnd() * 0.03);
    }
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aColor', new THREE.Float32BufferAttribute(col, 3));
  g.setAttribute('aSize', new THREE.Float32BufferAttribute(size, 1));
  g.setAttribute('aPhase', new THREE.Float32BufferAttribute(phase, 1));
  return { geometry: g, knots, count: size.length };
}

function buildGas(knots) {
  const rnd = mulberry32(77);
  const items = []; // [x,y,z, scale, r,g,b, alpha]
  const tmp = new THREE.Color();

  // Diffuse core glow
  for (let i = 0; i < 70; i++) {
    const x = gaussian(rnd) * 0.9;
    const y = gaussian(rnd) * 0.35;
    const z = gaussian(rnd) * 0.9;
    tmp.copy(CORE_WARM).lerp(STAR_WARM, rnd() * 0.5);
    items.push([x, y, z, 2.2 + rnd() * 2.6, tmp.r, tmp.g, tmp.b, 0.07 + rnd() * 0.05]);
  }

  // Arm gas: warm inside, cool outside (brand nebula palette)
  for (let i = 0; i < 2600; i++) {
    const u = Math.pow(rnd(), 0.9);
    const r = MIN_R * 1.2 + u * (R * 1.02 - MIN_R * 1.2);
    const rn = r / R;
    const arm = Math.floor(rnd() * ARMS);
    const theta = armAngle(r, arm) + gaussian(rnd) * (0.1 + rn * 0.12);
    const y = gaussian(rnd) * 0.08;
    const p = rnd();
    if (rn < 0.4) tmp.copy(p < 0.55 ? NEB_ORANGE : NEB_PINK);
    else if (rn < 0.7) tmp.copy(p < 0.45 ? NEB_PINK : p < 0.75 ? NEB_PURPLE : NEB_BLUE);
    else tmp.copy(p < 0.6 ? NEB_BLUE : NEB_PURPLE);
    items.push([r * Math.cos(theta), y, r * Math.sin(theta), 0.7 + rnd() * 1.5, tmp.r, tmp.g, tmp.b, 0.03 + rnd() * 0.035]);
  }

  // Bright pink emission around each star-forming knot
  for (const [x, y, z] of knots) {
    const n = 1 + Math.floor(rnd() * 2);
    for (let j = 0; j < n; j++) {
      items.push([x + gaussian(rnd) * 0.08, y, z + gaussian(rnd) * 0.08, 0.35 + rnd() * 0.45, NEB_PINK.r, NEB_PINK.g, NEB_PINK.b, 0.18 + rnd() * 0.15]);
    }
  }
  return items;
}

function buildDust() {
  const rnd = mulberry32(5150);
  const items = [];
  for (let i = 0; i < 3200; i++) {
    const u = Math.pow(rnd(), 0.85);
    const r = MIN_R * 1.15 + u * (R * 0.92 - MIN_R * 1.15);
    const rn = r / R;
    const arm = Math.floor(rnd() * ARMS);
    // inner (trailing) edge of the arm
    const theta = armAngle(r, arm) - 0.2 - rn * 0.1 + gaussian(rnd) * 0.06;
    const y = gaussian(rnd) * 0.04;
    items.push([r * Math.cos(theta), y, r * Math.sin(theta), 0.45 + rnd() * 0.9, 0, 0, 0, (0.18 + rnd() * 0.3) * (1 - 0.4 * rn)]);
  }
  return items;
}

function buildBackground() {
  const rnd = mulberry32(123);
  const N = 22000;
  const pos = new Float32Array(N * 3);
  const col = new Float32Array(N * 3);
  const size = new Float32Array(N);
  const palette = [STAR_WHITE, STAR_WHITE, STAR_BLUE, STAR_WARM, STAR_PINK];
  for (let i = 0; i < N; i++) {
    const v = new THREE.Vector3(gaussian(rnd), gaussian(rnd), gaussian(rnd)).normalize().multiplyScalar(900);
    pos.set([v.x, v.y, v.z], i * 3);
    const b = 0.08 + Math.pow(rnd(), 6) * 1.1;
    const c = palette[Math.floor(rnd() * palette.length)];
    col.set([c.r * b, c.g * b, c.b * b], i * 3);
    size[i] = 1.4 + Math.pow(rnd(), 4) * 2.6;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aSize', new THREE.BufferAttribute(size, 1));
  return g;
}

// ---------------------------------------------------------------- shaders

const uniforms = {
  uTime: { value: 0 },
  uProj: { value: projScale },
  uScale: { value: height / 1920 },
  // Exposure knobs: everything is additive, so these set the overall balance.
  uStarGain: { value: 0.12 },
  uGasGain: { value: 0.24 },
  uDustGain: { value: 1.6 },
};

// Differential rotation: solid-body inside ~2 units, flat rotation curve outside.
const SPIN_GLSL = /* glsl */ `
  uniform float uTime;
  vec3 spin(vec3 p) {
    float r = length(p.xz);
    float a = uTime * 0.25 / max(r, 2.0) + uTime * 0.012;
    float c = cos(a), s = sin(a);
    return vec3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
  }
`;

const NOISE_GLSL = /* glsl */ `
  float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
  float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
  }
  float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 11.7; a *= 0.5; }
    return v;
  }
`;

const starMaterial = new THREE.ShaderMaterial({
  uniforms,
  vertexShader: /* glsl */ `
    ${SPIN_GLSL}
    uniform float uProj;
    uniform float uStarGain;
    attribute vec3 aColor;
    attribute float aSize;
    attribute float aPhase;
    varying vec3 vColor;
    varying float vGain;
    void main() {
      vec4 mv = modelViewMatrix * vec4(spin(position), 1.0);
      gl_Position = projectionMatrix * mv;
      float px = aSize * uProj / max(-mv.z, 0.01);
      // Below 2px, keep the sprite at 2px and fade it by area, so tiny stars
      // dim smoothly instead of flickering between 0 and 1 pixel.
      vGain = min(1.0, (px * px) / 4.0) * (0.85 + 0.15 * sin(uTime * 1.7 + aPhase));
      gl_PointSize = clamp(px, 2.0, 48.0);
      // Fade stars right in front of the lens
      vGain *= smoothstep(0.15, 0.8, -mv.z);
      vColor = aColor * uStarGain;
    }
  `,
  fragmentShader: /* glsl */ `
    varying vec3 vColor;
    varying float vGain;
    void main() {
      float d = length(gl_PointCoord - 0.5) * 2.0;
      float a = exp(-d * d * 7.0) + 0.12 * exp(-d * d * 2.0);
      a *= 1.0 - smoothstep(0.85, 1.0, d);
      gl_FragColor = vec4(min(vColor * a * vGain, vec3(8.0)), 1.0);
    }
  `,
  transparent: true,
  depthWrite: false,
  blending: THREE.CustomBlending,
  blendSrc: THREE.OneFactor,
  blendDst: THREE.OneFactor,
});

function billboardMaterial({ dust }) {
  const m = new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */ `
      ${SPIN_GLSL}
      uniform float uGasGain;
      uniform float uDustGain;
      attribute vec3 aOffset;
      attribute vec4 aData; // scale, r, g, b
      attribute float aAlpha;
      attribute float aSeed;
      varying vec2 vUv;
      varying vec3 vColor;
      varying float vAlpha;
      varying float vSeed;
      void main() {
        vec4 mv = modelViewMatrix * vec4(spin(aOffset), 1.0);
        float rot = aSeed * 6.2831 + uTime * 0.02 * (aSeed - 0.5);
        float c = cos(rot), s = sin(rot);
        vec2 q = mat2(c, -s, s, c) * position.xy;
        mv.xy += q * aData.x;
        gl_Position = projectionMatrix * mv;
        vUv = uv;
        vColor = aData.yzw;
        // fade puffs that get close to the lens so they never fill the frame
        vAlpha = aAlpha * ${dust ? 'uDustGain' : 'uGasGain'} * smoothstep(0.4, 2.5, -mv.z);
        vSeed = aSeed;
      }
    `,
    fragmentShader: /* glsl */ `
      uniform float uTime;
      ${NOISE_GLSL}
      varying vec2 vUv;
      varying vec3 vColor;
      varying float vAlpha;
      varying float vSeed;
      void main() {
        float d = length(vUv - 0.5) * 2.0;
        float fall = 1.0 - smoothstep(0.0, 1.0, d);
        fall *= fall;
        float n = fbm(vUv * 2.6 + vSeed * 37.0 + vec2(uTime * 0.025, -uTime * 0.018));
        float a = fall * smoothstep(${dust ? '0.35, 0.8' : '0.22, 0.85'}, n) * vAlpha;
        ${dust
          ? 'gl_FragColor = vec4(vec3(0.62, 0.78, 0.95) * a, 1.0); // absorbs blue a bit more than red'
          : 'gl_FragColor = vec4(vColor * a, 1.0);'}
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.CustomBlending,
    // gas: dst + src (additive); dust: dst * (1 - src) (absorption)
    blendSrc: dust ? THREE.ZeroFactor : THREE.OneFactor,
    blendDst: dust ? THREE.OneMinusSrcColorFactor : THREE.OneFactor,
    // leave the alpha channel alone (otherwise dust writes alpha 0)
    blendSrcAlpha: THREE.ZeroFactor,
    blendDstAlpha: THREE.OneFactor,
  });
  return m;
}

function billboardMesh(items, material, seed) {
  const rnd = mulberry32(seed);
  const base = new THREE.PlaneGeometry(1, 1);
  const g = new THREE.InstancedBufferGeometry();
  g.index = base.index;
  g.setAttribute('position', base.getAttribute('position'));
  g.setAttribute('uv', base.getAttribute('uv'));
  const off = new Float32Array(items.length * 3);
  const data = new Float32Array(items.length * 4);
  const alpha = new Float32Array(items.length);
  const sd = new Float32Array(items.length);
  items.forEach((it, i) => {
    off.set(it.slice(0, 3), i * 3);
    data.set(it.slice(3, 7), i * 4);
    alpha[i] = it[7];
    sd[i] = rnd();
  });
  g.setAttribute('aOffset', new THREE.InstancedBufferAttribute(off, 3));
  g.setAttribute('aData', new THREE.InstancedBufferAttribute(data, 4));
  g.setAttribute('aAlpha', new THREE.InstancedBufferAttribute(alpha, 1));
  g.setAttribute('aSeed', new THREE.InstancedBufferAttribute(sd, 1));
  g.instanceCount = items.length;
  const mesh = new THREE.Mesh(g, material);
  mesh.frustumCulled = false;
  return mesh;
}

// ---------------------------------------------------------------- assemble

const stars = buildStars();
const starPoints = new THREE.Points(stars.geometry, starMaterial);
starPoints.frustumCulled = false;

const gas = billboardMesh(buildGas(stars.knots), billboardMaterial({ dust: false }), 1);
const dust = billboardMesh(buildDust(), billboardMaterial({ dust: true }), 2);

const bg = new THREE.Points(
  buildBackground(),
  new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */ `
      uniform float uScale;
      attribute vec3 aColor;
      attribute float aSize;
      varying vec3 vColor;
      void main() {
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        gl_PointSize = aSize * uScale;
        vColor = aColor;
      }
    `,
    fragmentShader: /* glsl */ `
      varying vec3 vColor;
      void main() {
        float d = length(gl_PointCoord - 0.5) * 2.0;
        gl_FragColor = vec4(vColor * exp(-d * d * 5.0), 1.0);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  }),
);
bg.frustumCulled = false;

bg.renderOrder = 0;
gas.renderOrder = 1;
starPoints.renderOrder = 2;
dust.renderOrder = 3;

const galaxy = new THREE.Group();
galaxy.add(gas, starPoints, dust);
galaxy.rotation.z = 0.08; // slight tilt so the disk is not perfectly level in frame
scene.add(bg, galaxy);

// Debug: ?hide=gas,dust,stars,bg hides layers; ?nopost renders without the composer.
const params = new URLSearchParams(location.search);
const hidden = new Set((params.get('hide') ?? '').split(','));
gas.visible = !hidden.has('gas');
dust.visible = !hidden.has('dust');
starPoints.visible = !hidden.has('stars');
bg.visible = !hidden.has('bg');
const noPost = params.has('nopost');

// ---------------------------------------------------------------- post

const target = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples: 4 });
const composer = new EffectComposer(renderer, target);
composer.setPixelRatio(1);
composer.setSize(width, height);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(width, height), 0.85, 0.6, 0.18);
composer.addPass(bloom);
composer.addPass(new OutputPass());

const finish = new ShaderPass({
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uFade: { value: 1 },
    uRes: { value: new THREE.Vector2(width, height) },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform float uFade;
    uniform vec2 uRes;
    varying vec2 vUv;
    float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 q = vUv - 0.5;
      q.x *= uRes.x / uRes.y;
      float v = 1.0 - smoothstep(0.2, 0.85, length(q));
      c.rgb *= mix(0.5, 1.0, v);
      c.rgb += (h(vUv * uRes + fract(uTime * 7.31) * 113.0) - 0.5) * 0.03; // grain, also breaks banding
      c.rgb *= uFade;
      gl_FragColor = c;
    }
  `,
});
composer.addPass(finish);

// ---------------------------------------------------------------- timeline

const target3 = new THREE.Vector3();

function shot1(p) {
  // high wide view, slow push-in and orbit
  const e = lerp(p, easeInOutSine(p), 0.5);
  const dist = lerp(31, 24.5, e);
  const elev = THREE.MathUtils.degToRad(lerp(56, 47, e));
  const az = lerp(0.15, 0.42, e);
  camera.position.set(dist * Math.cos(elev) * Math.sin(az), dist * Math.sin(elev), dist * Math.cos(elev) * Math.cos(az));
  camera.up.set(Math.sin(lerp(0.04, -0.02, e)), 1, 0).normalize();
  target3.set(0, 0, 0);
  camera.lookAt(target3);
}

function shot2(p) {
  // grazing pass over the outer disk toward the glowing core
  const e = lerp(p, easeInOutSine(p), 0.5);
  const az = lerp(2.35, 2.08, e);
  const r = lerp(12.5, 9.2, e);
  const y = lerp(1.35, 0.75, e);
  camera.position.set(r * Math.cos(az), y, r * Math.sin(az));
  camera.up.set(0, 1, 0);
  target3.set(0, lerp(0.6, 0.35, e), 0);
  camera.lookAt(target3);
  camera.rotateZ(lerp(-0.05, 0.03, e));
}

function render(t) {
  uniforms.uTime.value = t;
  finish.uniforms.uTime.value = t;

  let fade;
  if (t < 3) {
    shot1(t / 3);
    fade = smoothstep(0, 0.5, t) * (1 - smoothstep(2.75, 3.0, t));
  } else {
    shot2((t - 3) / 3);
    fade = smoothstep(3.0, 3.3, t) * (1 - smoothstep(5.5, 6.0, t));
  }
  finish.uniforms.uFade.value = fade;
  if (noPost) renderer.render(scene, camera);
  else composer.render();
}

console.log(`stars: ${stars.count}`);
stage.run(render);
