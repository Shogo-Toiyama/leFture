import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent, TouchEvent, WheelEvent } from 'react';

const BOTTOM_TOLERANCE = 2;
const NEAR_BOTTOM = 96;
const RESUME_WINDOW_MS = 500;

function distanceToBottom(el: HTMLDivElement): number {
  return el.scrollHeight - el.clientHeight - el.scrollTop;
}

export function useChatScroll(
  messages: readonly unknown[],
  loading: boolean,
  showGate: boolean,
  isGenerating: boolean,
) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const threadRef = useRef<HTMLDivElement>(null);
  const following = useRef(true);
  const opening = useRef(true);
  const wasGenerating = useRef(false);
  const lastScrollTop = useRef(0);
  const resumeUntil = useRef(0);
  const held = useRef({ pointers: new Set<number>(), touch: false, startTop: 0, wasFollowing: true });
  const scrollSnapshot = useRef<{ scrollHeight: number; scrollTop: number } | null>(null);
  const [showJumpToBottom, setShowJumpToBottom] = useState(false);

  const isHolding = useCallback(() => held.current.touch || held.current.pointers.size > 0, []);

  const syncScroll = useCallback((forceBottom = false) => {
    const el = scrollRef.current;
    if (!el) return;
    if (forceBottom || (isGenerating && following.current && !isHolding())) {
      el.scrollTop = el.scrollHeight;
      lastScrollTop.current = el.scrollTop;
    }
    setShowJumpToBottom(distanceToBottom(el) > BOTTOM_TOLERANCE);
  }, [isGenerating, isHolding]);

  const jumpToBottom = useCallback(() => {
    resumeUntil.current = 0;
    following.current = true;
    syncScroll(true);
  }, [syncScroll]);

  const prepareToSend = useCallback((followIfNear = false) => {
    const el = scrollRef.current;
    opening.current = false;
    resumeUntil.current = 0;
    const tolerance = followIfNear && el ? el.clientHeight : BOTTOM_TOLERANCE;
    following.current = Boolean(el && !isHolding() && distanceToBottom(el) <= tolerance);
  }, [isHolding]);

  const captureBeforePrepend = useCallback(() => {
    const el = scrollRef.current;
    if (el) scrollSnapshot.current = { scrollHeight: el.scrollHeight, scrollTop: el.scrollTop };
  }, []);

  useLayoutEffect(() => {
    const finishedReply = wasGenerating.current && !isGenerating && !loading;
    wasGenerating.current = isGenerating;
    const el = scrollRef.current;
    if (!el) return;
    // Loading or clearing a conversation resets its position. Adopting the ID
    // of a newly sent thread does neither while its reply is streaming.
    if (loading || messages.length === 0) {
      opening.current = true;
      following.current = true;
      resumeUntil.current = 0;
      scrollSnapshot.current = null;
    }
    if (!isGenerating) resumeUntil.current = 0;
    const openAtBottom = opening.current && !loading && messages.length > 0;
    if (openAtBottom) opening.current = false;
    const snapshot = scrollSnapshot.current;
    if (snapshot) {
      scrollSnapshot.current = null;
      el.scrollTop = snapshot.scrollTop + Math.max(0, el.scrollHeight - snapshot.scrollHeight);
      lastScrollTop.current = el.scrollTop;
    }
    // The final commit lays out the citations and message actions.
    const followFinalReply = finishedReply && following.current;
    syncScroll((openAtBottom || followFinalReply) && !isHolding());
  }, [isGenerating, isHolding, loading, messages, syncScroll]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const observer = new ResizeObserver(() => syncScroll());
    observer.observe(el);
    if (threadRef.current) observer.observe(threadRef.current);
    return () => observer.disconnect();
  }, [showGate, syncScroll]);

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    const movement = el.scrollTop - lastScrollTop.current;
    lastScrollTop.current = el.scrollTop;
    const distance = distanceToBottom(el);
    // Also catch native scrollbar moves when the browser handles the pointer.
    if (movement < 0 && distance > BOTTOM_TOLERANCE) following.current = false;
    if (
      isGenerating &&
      !following.current &&
      !isHolding() &&
      movement > 0 &&
      (distance <= BOTTOM_TOLERANCE ||
        (performance.now() < resumeUntil.current && distance <= NEAR_BOTTOM))
    ) {
      jumpToBottom();
      return;
    }
    setShowJumpToBottom(distance > BOTTOM_TOLERANCE);
  };

  const noteScrollInput = (towardBottom: boolean) => {
    const el = scrollRef.current;
    if (!el || !isGenerating) return;
    lastScrollTop.current = el.scrollTop;
    following.current = false;
    resumeUntil.current = towardBottom ? performance.now() + RESUME_WINDOW_MS : 0;
    if (towardBottom && !isHolding() && distanceToBottom(el) <= BOTTOM_TOLERANCE) {
      jumpToBottom();
    }
  };

  const onWheel = (event: WheelEvent<HTMLDivElement>) => {
    if (event.deltaY !== 0 && !event.ctrlKey) noteScrollInput(event.deltaY > 0);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.target !== event.currentTarget) return;
    switch (event.key) {
      case 'ArrowDown':
      case 'PageDown':
      case 'End':
        noteScrollInput(true);
        break;
      case 'ArrowUp':
      case 'PageUp':
      case 'Home':
        noteScrollInput(false);
        break;
      case ' ':
        noteScrollInput(!event.shiftKey);
        break;
    }
  };

  const beginHeldInput = () => {
    const el = scrollRef.current;
    if (!el || isHolding()) return;
    held.current.startTop = el.scrollTop;
    held.current.wasFollowing = following.current;
    following.current = false;
    resumeUntil.current = 0;
  };

  const finishHeldInput = useCallback(() => {
    const el = scrollRef.current;
    if (!el || !isGenerating || isHolding()) return;
    lastScrollTop.current = el.scrollTop;
    resumeUntil.current = performance.now() + RESUME_WINDOW_MS;
    const movement = el.scrollTop - held.current.startTop;
    if ((movement > 0 || (movement === 0 && held.current.wasFollowing)) &&
        distanceToBottom(el) <= NEAR_BOTTOM) {
      jumpToBottom();
    }
  }, [isGenerating, isHolding, jumpToBottom]);

  useEffect(() => {
    const release = (event: globalThis.PointerEvent) => {
      if (held.current.pointers.delete(event.pointerId)) finishHeldInput();
    };
    const clearHeldInput = () => {
      held.current.pointers.clear();
      held.current.touch = false;
      resumeUntil.current = 0;
    };
    window.addEventListener('pointerup', release, true);
    window.addEventListener('pointercancel', release, true);
    window.addEventListener('blur', clearHeldInput);
    return () => {
      window.removeEventListener('pointerup', release, true);
      window.removeEventListener('pointercancel', release, true);
      window.removeEventListener('blur', clearHeldInput);
    };
  }, [finishHeldInput]);

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.pointerType === 'touch' || event.button !== 0) return;
    beginHeldInput();
    held.current.pointers.add(event.pointerId);
  };

  // Browsers cancel pointer events once a touch becomes a native scroll.
  const onTouchStart = () => {
    beginHeldInput();
    held.current.touch = true;
  };

  const onTouchEnd = (event: TouchEvent<HTMLDivElement>) => {
    if (event.touches.length > 0 || !held.current.touch) return;
    held.current.touch = false;
    finishHeldInput();
  };

  return {
    scrollRef, threadRef, showJumpToBottom, jumpToBottom, prepareToSend,
    captureBeforePrepend, onScroll, onWheel, onKeyDown, onPointerDown, onTouchStart, onTouchEnd,
  };
}
