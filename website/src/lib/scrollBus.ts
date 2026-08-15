/**
 * A single rAF loop that every scroll-driven visual on the page subscribes to.
 *
 * Instead of each component attaching its own `scroll` listener (which fires
 * at wildly different rates across browsers and causes layout thrash), we read
 * `scrollY` once per frame and hand out a *smoothed* value. The smoothing is
 * what makes the hero choreography feel like it has weight rather than
 * snapping 1:1 to the wheel.
 *
 * The loop parks itself as soon as the smoothed value has caught up, so an idle
 * page costs nothing.
 */

export type ScrollListener = (y: number, viewportHeight: number) => void;

const listeners = new Set<ScrollListener>();

let smoothed = 0;
let viewportHeight = typeof window !== 'undefined' ? window.innerHeight : 0;
let rafId: number | null = null;
let dirty = true;

/** How much of the remaining distance we close each frame. Lower = heavier. */
const EASING = 0.16;
/** Below this many pixels we consider the animation settled. */
const SETTLE_PX = 0.3;

function emit() {
  for (const listener of listeners) listener(smoothed, viewportHeight);
}

function tick() {
  const target = window.scrollY;
  const distance = target - smoothed;

  if (Math.abs(distance) < SETTLE_PX) {
    smoothed = target;
    dirty = false;
  } else {
    smoothed += distance * EASING;
  }

  emit();

  if (listeners.size > 0 && (dirty || Math.abs(target - smoothed) >= SETTLE_PX)) {
    rafId = requestAnimationFrame(tick);
  } else {
    rafId = null;
  }
}

function wake() {
  dirty = true;
  if (rafId === null && listeners.size > 0) {
    rafId = requestAnimationFrame(tick);
  }
}

function onResize() {
  viewportHeight = window.innerHeight;
  wake();
}

export function subscribeScroll(listener: ScrollListener): () => void {
  const isFirst = listeners.size === 0;
  listeners.add(listener);

  if (isFirst) {
    window.addEventListener('scroll', wake, { passive: true });
    window.addEventListener('resize', onResize);
    smoothed = window.scrollY;
    viewportHeight = window.innerHeight;
  }

  // Give the new subscriber a value immediately so it never renders a frame
  // with a stale default.
  listener(smoothed, viewportHeight);
  wake();

  return () => {
    listeners.delete(listener);
    if (listeners.size === 0) {
      window.removeEventListener('scroll', wake);
      window.removeEventListener('resize', onResize);
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    }
  };
}

/** 0 → 1 ramp with eased ends. Handy for mapping scroll ranges. */
export function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

export function clamp01(x: number): number {
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

export const prefersReducedMotion = (): boolean =>
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;
