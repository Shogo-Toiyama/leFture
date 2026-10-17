import React, { useEffect, useRef, useState } from 'react';
import { CHAT_DOCK_MIN_PX, clampDockWidth, maxDockWidth } from '../../lib/chatDockWidth';

interface ChatDockResizerProps {
  /** いま使っている幅(スクリーンリーダー・キー操作の基準) */
  width: number;
  viewportWidth: number;
  label: string;
  /** ドラッグ中、動くたびに(1フレームに1回まで)呼ばれる。保存はしない。 */
  onLive: (px: number) => void;
  /** 指を離した・キーで動かした: この幅で確定して保存する。 */
  onCommit: (px: number) => void;
  /** ダブルクリック: 初期値に戻す。 */
  onReset: () => void;
}

/** キーで動かす幅(Shiftを押すと4倍) */
const KEY_STEP_PX = 24;

/**
 * パネルの左端に置く、幅を変えるためのつかみ部分(見えるのはホバー・フォーカス・ドラッグ中)。
 * パネルは右に固定されているので、左へ動かすと広がり、右へ動かすと狭まる。
 * pointer captureで、ポインターがページの要素に奪われてもドラッグが切れないようにする。
 */
export const ChatDockResizer: React.FC<ChatDockResizerProps> = ({
  width,
  viewportWidth,
  label,
  onLive,
  onCommit,
  onReset,
}) => {
  // 見た目(is-dragging)はstate、判定はref。押してすぐ離しても、描き直しを待たずに正しく終われる
  const [dragging, setDragging] = useState(false);
  const active = useRef(false);
  const moved = useRef(false);
  const frame = useRef(0);
  const latest = useRef(width);

  // ドラッグ中にこの部品が消えても(パネルを閉じた等)、bodyに付けた印を残さない
  useEffect(
    () => () => {
      cancelAnimationFrame(frame.current);
      document.body.classList.remove('is-resizing-chat');
    },
    []
  );

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    latest.current = width;
    active.current = true;
    moved.current = false;
    setDragging(true);
    document.body.classList.add('is-resizing-chat');
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!active.current) return;
    // つかみ部分の中心が指に付いてくるように、右端からの距離をそのまま幅にする
    latest.current = clampDockWidth(window.innerWidth - event.clientX, window.innerWidth);
    moved.current = true;
    if (frame.current) return;
    frame.current = requestAnimationFrame(() => {
      frame.current = 0;
      onLive(latest.current);
    });
  };

  const finish = () => {
    if (!active.current) return;
    active.current = false;
    cancelAnimationFrame(frame.current);
    frame.current = 0;
    setDragging(false);
    document.body.classList.remove('is-resizing-chat');
    // クリックしただけ(動かしていない)なら何も変えない。画面が狭くて丸めていた幅を、好みの幅として保存してしまわないように
    if (!moved.current) return;
    // 間引かれた最後のフレームの分まで、変数を最終の幅に合わせてから確定する
    onLive(latest.current);
    onCommit(latest.current);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const step = event.shiftKey ? KEY_STEP_PX * 4 : KEY_STEP_PX;
    // 左に動かすと広がる(マウスと同じ向き)
    if (event.key === 'ArrowLeft') onCommit(clampDockWidth(width + step, viewportWidth));
    else if (event.key === 'ArrowRight') onCommit(clampDockWidth(width - step, viewportWidth));
    else if (event.key === 'Home') onReset();
    else return;
    event.preventDefault();
  };

  return (
    <div
      className={`chat-dock-resizer${dragging ? ' is-dragging' : ''}`}
      role="separator"
      aria-orientation="vertical"
      aria-label={label}
      aria-valuemin={CHAT_DOCK_MIN_PX}
      aria-valuemax={maxDockWidth(viewportWidth)}
      aria-valuenow={width}
      tabIndex={0}
      title={label}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={finish}
      onPointerCancel={finish}
      onDoubleClick={onReset}
      onKeyDown={onKeyDown}
    />
  );
};
