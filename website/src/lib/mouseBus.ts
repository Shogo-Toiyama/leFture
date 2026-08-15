import { prefersReducedMotion } from './scrollBus';

type MouseListener = (x: number, y: number) => void;

const listeners = new Set<MouseListener>();

let mouseX = 0; // -1 to 1 (interpolated)
let mouseY = 0;
let targetX = 0;
let targetY = 0;
let isInitialized = false;
let rafId = 0;

function update() {
  if (prefersReducedMotion()) {
    mouseX = 0;
    mouseY = 0;
  } else {
    // Smooth dampening
    mouseX += (targetX - mouseX) * 0.08;
    mouseY += (targetY - mouseY) * 0.08;
  }

  for (const listener of listeners) {
    listener(mouseX, mouseY);
  }

  rafId = requestAnimationFrame(update);
}

function handlePointerMove(e: PointerEvent) {
  const w = window.innerWidth || 1;
  const h = window.innerHeight || 1;
  targetX = (e.clientX / w) * 2 - 1;
  targetY = (e.clientY / h) * 2 - 1;
}

function init() {
  if (isInitialized || typeof window === 'undefined') return;
  isInitialized = true;

  if (window.matchMedia('(hover: hover)').matches) {
    window.addEventListener('pointermove', handlePointerMove, { passive: true });
    rafId = requestAnimationFrame(update);
  }
}

export function subscribeMouse(listener: MouseListener): () => void {
  init();
  listeners.add(listener);
  // Initial fire
  listener(mouseX, mouseY);

  return () => {
    listeners.delete(listener);
    if (listeners.size === 0 && isInitialized) {
      window.removeEventListener('pointermove', handlePointerMove);
      cancelAnimationFrame(rafId);
      isInitialized = false;
    }
  };
}
