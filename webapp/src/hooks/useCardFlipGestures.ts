import { useCallback, useRef } from 'react';

interface Options {
  onPrevious: () => void;
  onNext: () => void;
  /** カード幅に対する、タップで「戻る」とみなす左側の割合。 */
  tapZoneRatio?: number;
}

interface GestureHandlers {
  onPointerDown: (event: React.PointerEvent<HTMLElement>) => void;
  onPointerUp: (event: React.PointerEvent<HTMLElement>) => void;
  onPointerCancel: () => void;
}

const SWIPE_DISTANCE = 48;
const TAP_SLOP = 10;
const TAP_DURATION = 500;

/**
 * カードをスワイプ/タップでめくる。review_cards_viewer_page.dart と同じ操作感。
 *
 * タッチのときだけ有効にする。マウスの横ドラッグは本文のテキスト選択であり、
 * マウスのタップは注釈をつつく操作なので、奪ってしまうとカードが読めなくなる。
 * デスクトップは左右の矢印ボタンとキーボードで送る。
 */
export function useCardFlipGestures({
  onPrevious,
  onNext,
  tapZoneRatio = 0.3,
}: Options): GestureHandlers {
  const start = useRef<{ x: number; y: number; time: number } | null>(null);

  const onPointerDown = useCallback((event: React.PointerEvent<HTMLElement>) => {
    if (event.pointerType !== 'touch') return;
    start.current = { x: event.clientX, y: event.clientY, time: event.timeStamp };
    // 指がカードの外へ抜けてもpointerupを受け取れるようにする。
    // 縦スクロールをブラウザが引き取った場合はpointercancelが来るので、
    // カード内のスクロールを邪魔することはない。
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      /* 捕捉できない環境では素のイベントで拾う */
    }
  }, []);

  const onPointerUp = useCallback(
    (event: React.PointerEvent<HTMLElement>) => {
      const origin = start.current;
      start.current = null;
      if (event.currentTarget.hasPointerCapture?.(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId);
      }
      if (!origin || event.pointerType !== 'touch') return;

      // 注釈や操作ボタンの上での操作は、そちらの仕事なので邪魔しない。
      const target = event.target as HTMLElement | null;
      if (target?.closest('button, a, [data-annotation-id], [data-annotation-ui]')) return;

      // 文字を選んでいる最中のタップは、選択の解除が目的なのでめくらない。
      const selection = window.getSelection();
      if (selection && !selection.isCollapsed) return;

      const dx = event.clientX - origin.x;
      const dy = event.clientY - origin.y;

      // 横スワイプ: 縦より横に動いていればめくる。
      if (Math.abs(dx) >= SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) onNext();
        else onPrevious();
        return;
      }

      // タップ: 指が動いておらず、長押しでもないとき。
      const moved = Math.hypot(dx, dy) > TAP_SLOP;
      if (moved || event.timeStamp - origin.time > TAP_DURATION) return;

      const box = event.currentTarget.getBoundingClientRect();
      if (box.width === 0) return;
      const ratio = (event.clientX - box.left) / box.width;
      if (ratio < tapZoneRatio) onPrevious();
      else onNext();
    },
    [onPrevious, onNext, tapZoneRatio]
  );

  const onPointerCancel = useCallback(() => {
    start.current = null;
  }, []);

  return { onPointerDown, onPointerUp, onPointerCancel };
}
