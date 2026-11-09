// Recording page, redrawn on canvases in Flutter logical points (pt).
//
// Layout and colors come from two sources:
//   - user_interface/lib/presentation/pages/recording/recording_page.dart and
//     widgets/audio_waveform_visualizer.dart (sizes, colors, animation timings)
//   - video/assets/screenshots/recording/*.png (1284x2778 = 428x926 pt at 3x) for positions
//
// Each part is its own layer so the 3D scene can lift it off the screen.
// Coordinates below are absolute screen pt (0,0 = top-left of the 428x926 screen).

export const SCREEN_W = 428;
export const SCREEN_H = 926;
export const PX_PER_PT = 4; // texture resolution: 4 px per pt (close-ups stay sharp)

// AppColors (user_interface/lib/presentation/themes/app_colors.dart)
export const COLORS = {
  starGold: '#FFB300',
  growthGreen: '#4CAF50',
  correctionRed: '#E53935',
  void: '#111422',
  textStarlight: '#F2F2F2',
  textComet: '#8E99A6',
  glassWhiteLow: 'rgba(255,255,255,0.10)',
  glassWhiteHigh: 'rgba(255,255,255,0.20)',
  glassBorder: 'rgba(255,255,255,0.30)',
};

const TEXT = 'system-ui, -apple-system, "Helvetica Neue", sans-serif';

export async function loadFonts() {
  const faces = [
    new FontFace('MI', 'url(/node_modules/material-icons/iconfont/material-icons.woff2)'),
    new FontFace('MIO', 'url(/node_modules/material-icons/iconfont/material-icons-outlined.woff2)'),
    new FontFace('MIR', 'url(/node_modules/material-icons/iconfont/material-icons-round.woff2)'),
  ];
  for (const f of faces) document.fonts.add(await f.load());
  await document.fonts.ready;
}

// ---------------------------------------------------------------- helpers

function rgba(hex, a) {
  const v = hex.replace('#', '');
  return `rgba(${parseInt(v.slice(0, 2), 16)},${parseInt(v.slice(2, 4), 16)},${parseInt(v.slice(4, 6), 16)},${a})`;
}

function mixHex(a, b, t) {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  const c = pa.map((v, i) => Math.round(v + (pb[i] - v) * t));
  return `#${c.map((v) => v.toString(16).padStart(2, '0')).join('')}`;
}
export { mixHex };

function rrect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function text(ctx, str, x, y, { size, weight = 400, color, align = 'left', spacing = 0, font = TEXT }) {
  ctx.font = `${weight} ${size}px ${font}`;
  ctx.letterSpacing = `${spacing}px`;
  ctx.textAlign = align;
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = color;
  ctx.fillText(str, x, y);
  ctx.letterSpacing = '0px';
}

function icon(ctx, name, cx, cy, size, color, family = 'MI') {
  ctx.font = `${size}px ${family}`;
  ctx.letterSpacing = '0px';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = color;
  ctx.fillText(name, cx, cy);
}

/**
 * A layer is a canvas covering rect (x, y, w, h) in screen pt, plus `pad` pt of
 * margin on every side for glows. draw(ctx, state) paints in absolute screen pt.
 */
export function makeLayer({ name, x, y, w, h, pad = 0, draw }) {
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil((w + pad * 2) * PX_PER_PT);
  canvas.height = Math.ceil((h + pad * 2) * PX_PER_PT);
  const ctx = canvas.getContext('2d');
  return {
    name,
    x, y, w, h, pad,
    canvas,
    // centre of the layer in screen pt
    cx: x + w / 2,
    cy: y + h / 2,
    redraw(state) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.setTransform(PX_PER_PT, 0, 0, PX_PER_PT, (pad - x) * PX_PER_PT, (pad - y) * PX_PER_PT);
      draw(ctx, state);
    },
  };
}

// ---------------------------------------------------------------- layers

const SCREEN_RADIUS = 55; // iPhone Pro Max display corner radius in pt

/** Background, status bar, app bar with tabs, bottom upload bar. Same in both states. */
export const base = () =>
  makeLayer({
    name: 'base',
    x: 0, y: 0, w: SCREEN_W, h: SCREEN_H,
    draw(ctx) {
      rrect(ctx, 0, 0, SCREEN_W, SCREEN_H, SCREEN_RADIUS);
      ctx.save();
      ctx.clip();
      ctx.fillStyle = COLORS.void;
      ctx.fillRect(0, 0, SCREEN_W, SCREEN_H);

      // status bar
      text(ctx, '2:30', 74, 34, { size: 17, weight: 600, color: '#FFFFFF', align: 'center' });
      icon(ctx, 'wifi', 352, 27, 17, '#FFFFFF');
      rrect(ctx, 368, 20.5, 25, 12, 3.5);
      ctx.strokeStyle = 'rgba(255,255,255,0.45)';
      ctx.lineWidth = 1;
      ctx.stroke();
      rrect(ctx, 370, 22.5, 12, 8, 2);
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      rrect(ctx, 394.5, 24.5, 1.6, 4, 0.8);
      ctx.fillStyle = 'rgba(255,255,255,0.45)';
      ctx.fill();
      // Dynamic Island
      rrect(ctx, 214 - 63, 11, 126, 37, 18.5);
      ctx.fillStyle = '#000000';
      ctx.fill();

      // app bar: close + tabs (mic selected, forum)
      icon(ctx, 'close', 28, 75, 24, '#FFFFFF');
      icon(ctx, 'mic', 157, 73, 24, COLORS.starGold);
      icon(ctx, 'forum', 327, 73, 24, COLORS.textComet, 'MIO');
      ctx.fillStyle = 'rgba(255,255,255,0.18)';
      ctx.fillRect(72, 98, 340, 1);
      rrect(ctx, 145, 96, 24, 3, 1.5);
      ctx.fillStyle = COLORS.starGold;
      ctx.fill();

      // bottom bar
      ctx.fillStyle = 'rgba(255,255,255,0.14)';
      ctx.fillRect(0, 841, SCREEN_W, 1);
      rrect(ctx, 16, 857, 396, 54, 14);
      ctx.fillStyle = '#272B37';
      ctx.fill();
      text(ctx, 'Upload Recording', 214, 890, { size: 15.5, weight: 700, color: '#6E7684', align: 'center', spacing: 0.6 });

      // home indicator
      rrect(ctx, 214 - 67, 913, 134, 5, 2.5);
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      ctx.fill();
      ctx.restore();
    },
  });

export const courseCard = () =>
  makeLayer({
    name: 'course',
    x: 20.5, y: 123, w: 387.5, h: 74, pad: 18,
    draw(ctx) {
      const { x, y, w, h } = { x: 20.5, y: 123, w: 387.5, h: 74 };
      // soft gold glow behind the card
      ctx.save();
      ctx.shadowColor = rgba(COLORS.starGold, 0.16);
      ctx.shadowBlur = 18;
      rrect(ctx, x, y, w, h, 14);
      ctx.fillStyle = '#2A2618';
      ctx.fill();
      ctx.restore();
      const g = ctx.createLinearGradient(x, 0, x + w, 0);
      g.addColorStop(0, '#4A3F22');
      g.addColorStop(1, '#3B3727');
      rrect(ctx, x, y, w, h, 14);
      ctx.fillStyle = g;
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.22)';
      ctx.lineWidth = 1;
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(57, 160, 20, 0, Math.PI * 2);
      ctx.fillStyle = rgba(COLORS.starGold, 0.22);
      ctx.fill();
      icon(ctx, 'school', 57, 160, 22, COLORS.starGold, 'MIO');
      text(ctx, 'Course', 94, 156.5, { size: 11, color: COLORS.textComet, spacing: 1.2 });
      text(ctx, 'Guide & Notes', 94, 177.5, { size: 14, weight: 700, color: '#FFFFFF', spacing: 0.8 });
      icon(ctx, 'arrow_drop_down', 371, 160, 26, '#FFFFFF');
    },
  });

export const langChip = () =>
  makeLayer({
    name: 'chip',
    x: 101, y: 210, w: 226, h: 33, pad: 6,
    draw(ctx) {
      rrect(ctx, 101, 210, 226, 33, 16.5);
      ctx.fillStyle = 'rgba(255,255,255,0.05)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.26)';
      ctx.lineWidth = 1;
      ctx.stroke();
      icon(ctx, 'language', 122.5, 226.5, 15, COLORS.textComet);
      text(ctx, 'English', 134, 230.5, { size: 11.5, weight: 600, color: '#FFFFFF', spacing: 0.6 });
      ctx.fillStyle = 'rgba(255,255,255,0.3)';
      ctx.fillRect(188.5, 219, 1, 15);
      icon(ctx, 'offline_bolt', 206, 226.5, 15, COLORS.textComet, 'MIO');
      text(ctx, 'Realtime OFF', 217, 230.5, { size: 11.5, weight: 500, color: COLORS.textComet, spacing: 0.6 });
      icon(ctx, 'chevron_right', 305.5, 226.5, 14, COLORS.textComet);
    },
  });

/** state: { seconds, recording } */
export const timer = () =>
  makeLayer({
    name: 'timer',
    x: 90, y: 290, w: 248, h: 70, pad: 30,
    draw(ctx, { seconds, recordMix }) {
      const s = Math.floor(seconds);
      const str = `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
      ctx.save();
      // Flutter: Shadow(color: (recording ? red : gold).withAlpha(recording ? .45 : .22), blurRadius: 24)
      const shadowHex = mixHex(COLORS.starGold, COLORS.correctionRed, recordMix);
      ctx.shadowColor = rgba(shadowHex, 0.22 + 0.23 * recordMix);
      ctx.shadowBlur = 24 * PX_PER_PT * 0.5; // canvas blur is in device px; Flutter blurRadius ≈ 2σ
      ctx.font = `100 64px ${TEXT}`;
      ctx.fontVariantNumeric = 'tabular-nums';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = '#FFFFFF';
      ctx.fillText(str, 214, 347);
      ctx.restore();
    },
  });

/** Mic button: 140pt circle, gold idle → red recording (the pulse ring is 3D, not drawn here). */
export const micButton = () =>
  makeLayer({
    name: 'button',
    x: 144, y: 480, w: 140, h: 140, pad: 40,
    draw(ctx, { recordMix, iconSwap }) {
      const cx = 214;
      const cy = 550;
      const accent = mixHex(COLORS.starGold, COLORS.correctionRed, recordMix);
      // BoxShadow: alpha .25→.45, blur 18→30, spread 1→4
      ctx.save();
      ctx.shadowColor = rgba(accent, 0.25 + 0.2 * recordMix);
      ctx.shadowBlur = (18 + 12 * recordMix) * PX_PER_PT * 0.5;
      ctx.beginPath();
      ctx.arc(cx, cy, 70 + 1 + 3 * recordMix, 0, Math.PI * 2);
      ctx.fillStyle = rgba(accent, 0.35);
      ctx.fill();
      ctx.restore();
      // erase the solid fill used to cast the shadow, keep only the glow outside the circle
      ctx.save();
      ctx.globalCompositeOperation = 'destination-out';
      ctx.beginPath();
      ctx.arc(cx, cy, 70, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();

      // RadialGradient(accent .22 → .05) over the void background
      ctx.beginPath();
      ctx.arc(cx, cy, 70, 0, Math.PI * 2);
      ctx.fillStyle = COLORS.void;
      ctx.fill();
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, 70);
      g.addColorStop(0, rgba(accent, 0.42));
      g.addColorStop(1, rgba(accent, 0.3));
      ctx.fillStyle = g;
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = accent;
      ctx.beginPath();
      ctx.arc(cx, cy, 69, 0, Math.PI * 2);
      ctx.stroke();

      // AnimatedSwitcher with ScaleTransition (250ms): mic shrinks out, stop grows in
      const outScale = Math.max(0, 1 - iconSwap * 2);
      const inScale = Math.max(0, iconSwap * 2 - 1);
      if (outScale > 0) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.scale(outScale, outScale);
        icon(ctx, 'mic', 0, 0, 64, accent);
        ctx.restore();
      }
      if (inScale > 0) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.scale(inScale, inScale);
        icon(ctx, 'stop', 0, 0, 64, accent, 'MIR');
        ctx.restore();
      }
    },
  });

export const idleStatus = () =>
  makeLayer({
    name: 'idle',
    x: 20.5, y: 655, w: 387.5, h: 185, pad: 4,
    draw(ctx) {
      text(ctx, 'Ready to record', 214, 679, { size: 14, color: COLORS.textComet, align: 'center', spacing: 1.2 });
      ctx.fillStyle = 'rgba(255,255,255,0.16)';
      ctx.fillRect(20.5, 716.5, 173, 1);
      ctx.fillRect(235, 716.5, 173, 1);
      text(ctx, 'OR', 214, 720.5, { size: 11, weight: 600, color: COLORS.textComet, align: 'center', spacing: 1.2 });
      rrect(ctx, 20.5, 741, 387.5, 56, 14);
      ctx.fillStyle = 'rgba(255,255,255,0.07)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.16)';
      ctx.lineWidth = 1;
      ctx.stroke();
      icon(ctx, 'upload_file', 151, 769, 20, COLORS.textComet, 'MIO');
      text(ctx, 'Select audio file', 170, 774, { size: 14, color: COLORS.textComet, spacing: 1.2 });
      // top edge of the next card, cut off by the bottom bar
      rrect(ctx, 20.5, 829, 387.5, 40, 14);
      ctx.strokeStyle = 'rgba(255,255,255,0.16)';
      ctx.stroke();
    },
  });

export const recordingStatus = () =>
  makeLayer({
    name: 'recording',
    x: 20.5, y: 655, w: 387.5, h: 185, pad: 4,
    draw(ctx) {
      rrect(ctx, 150.5, 666, 127, 31, 15.5);
      ctx.fillStyle = rgba(COLORS.correctionRed, 0.1);
      ctx.fill();
      ctx.strokeStyle = rgba(COLORS.correctionRed, 0.45);
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(172.5, 681.5, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = COLORS.correctionRed;
      ctx.fill();
      text(ctx, 'Recording...', 185, 685.5, { size: 12.5, weight: 700, color: COLORS.correctionRed, spacing: 1 });
      icon(ctx, 'delete', 149, 721, 20, COLORS.textComet, 'MIO');
      text(ctx, 'Discard Recording', 167, 726, { size: 13.5, color: COLORS.textComet, spacing: 0.8 });
      rrect(ctx, 20.5, 778, 387.5, 45, 14);
      ctx.strokeStyle = 'rgba(255,255,255,0.2)';
      ctx.stroke();
      icon(ctx, 'settings', 47, 800.5, 20, COLORS.textComet, 'MIO');
      text(ctx, 'Settings', 68, 805, { size: 13.5, color: COLORS.textComet, spacing: 1.2 });
      icon(ctx, 'expand_more', 381, 800.5, 22, COLORS.textComet);
    },
  });

// ---------------------------------------------------------------- waveform model

/** Bar geometry from _WaveformPainter (width 380pt, 25 bars, 40% of width is spacing). */
export const WAVE = (() => {
  const count = 25;
  const width = 380;
  const left = 24;
  const height = 44;
  const totalSpacing = width * 0.4;
  const barWidth = (width - totalSpacing) / count;
  const spacing = totalSpacing / (count - 1);
  const xs = [];
  for (let i = 0; i < count; i++) {
    const normalized = Math.abs(i - count / 2) / (count / 2);
    xs.push({ x: left + i * (barWidth + spacing) + barWidth / 2, envelope: Math.sin(((1 - normalized) * Math.PI) / 2) });
  }
  return { count, height, barWidth, bars: xs, centerY: 407 };
})();
