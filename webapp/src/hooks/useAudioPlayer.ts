import { useCallback, useEffect, useRef, useState } from 'react';

export interface AudioPlayerState {
  /** <audio>に渡すref。ページ側で要素を描画する。 */
  ref: React.RefObject<HTMLAudioElement | null>;
  /** 秒 */
  position: number;
  /** 秒。メタデータが読めるまでは0。 */
  duration: number;
  playing: boolean;
  rate: number;
  ready: boolean;
  toggle: () => void;
  seek: (seconds: number) => void;
  skip: (deltaSeconds: number) => void;
  setRate: (rate: number) => void;
}

/**
 * <audio>要素の薄いラッパー。
 * timeupdateは秒4回程度しか飛ばずシークバーがカクつくので、再生中だけ
 * requestAnimationFrameで現在位置を読む。
 */
export function useAudioPlayer(src: string | null): AudioPlayerState {
  const ref = useRef<HTMLAudioElement | null>(null);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [rate, setRateState] = useState(1);
  const [ready, setReady] = useState(false);

  // 音源が変わったら状態を初期化する。
  useEffect(() => {
    setPosition(0);
    setDuration(0);
    setPlaying(false);
    setReady(false);
  }, [src]);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const onLoaded = () => {
      setDuration(Number.isFinite(element.duration) ? element.duration : 0);
      setReady(true);
    };
    const onTime = () => setPosition(element.currentTime);
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    const onEnded = () => setPlaying(false);

    element.addEventListener('loadedmetadata', onLoaded);
    element.addEventListener('durationchange', onLoaded);
    element.addEventListener('timeupdate', onTime);
    element.addEventListener('play', onPlay);
    element.addEventListener('pause', onPause);
    element.addEventListener('ended', onEnded);
    return () => {
      element.removeEventListener('loadedmetadata', onLoaded);
      element.removeEventListener('durationchange', onLoaded);
      element.removeEventListener('timeupdate', onTime);
      element.removeEventListener('play', onPlay);
      element.removeEventListener('pause', onPause);
      element.removeEventListener('ended', onEnded);
    };
  }, [src]);

  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    const tick = () => {
      const element = ref.current;
      if (element) setPosition(element.currentTime);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing]);

  const toggle = useCallback(() => {
    const element = ref.current;
    if (!element) return;
    if (element.paused) void element.play().catch(() => setPlaying(false));
    else element.pause();
  }, []);

  const seek = useCallback((seconds: number) => {
    const element = ref.current;
    if (!element) return;
    const max = Number.isFinite(element.duration) ? element.duration : seconds;
    const target = Math.min(Math.max(seconds, 0), max);
    element.currentTime = target;
    setPosition(target);
  }, []);

  const skip = useCallback(
    (delta: number) => {
      const element = ref.current;
      if (!element) return;
      seek(element.currentTime + delta);
    },
    [seek]
  );

  const setRate = useCallback((next: number) => {
    const element = ref.current;
    if (element) element.playbackRate = next;
    setRateState(next);
  }, []);

  return { ref, position, duration, playing, rate, ready, toggle, seek, skip, setRate };
}
