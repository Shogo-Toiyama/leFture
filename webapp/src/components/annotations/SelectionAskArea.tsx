import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useChatPanel } from '../../context/ChatPanelContext';
import { buildChatSelection } from '../../lib/chatSelection';
import { readSelectionOffsets, type SelectionOffsets } from '../../lib/markdownAnnotations';
import type { ChatScreenRef } from '../../types/chat';
import { floatingStyle } from './AnnotationLayer';

interface SelectionAskAreaProps {
  /** この中の文章を選んで「Ask」したときに添えるページ。 */
  screen: ChatScreenRef;
  className?: string;
  children: React.ReactNode;
}

/**
 * ハイライト・ノートを持たない読み物(Fun Fact)用の、選択→「Ask」だけの軽いツールバー。
 * Deep Notes / 復習カードのAnnotationLayerと同じ見た目・同じ選択の追従
 * (selectionchangeを主に、ポインタの上下をドラッグ確定の合図に)を、この領域の中だけで行う。
 * チャットパネルの外(ログイン前など)では何もしない。
 */
export const SelectionAskArea: React.FC<SelectionAskAreaProps> = ({ screen, className, children }) => {
  const chatPanel = useChatPanel();
  const containerRef = useRef<HTMLDivElement>(null);
  const [selection, setSelection] = useState<(SelectionOffsets & { flattenedText: string }) | null>(null);
  const enabled = chatPanel !== null;

  useEffect(() => {
    if (!enabled) return;
    let pointerDown = false;
    let onOwnUi = false;
    let frame = 0;

    const evaluate = () => {
      const container = containerRef.current;
      const offsets = container ? readSelectionOffsets(container, { clip: true }) : null;
      setSelection(offsets && container ? { ...offsets, flattenedText: container.textContent ?? '' } : null);
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(evaluate);
    };
    const isOwnUi = (target: EventTarget | null) =>
      target instanceof Element && Boolean(target.closest('[data-selection-ask-ui]'));

    const onPointerDown = (event: PointerEvent) => {
      onOwnUi = isOwnUi(event.target);
      pointerDown = !onOwnUi;
    };
    const onPointerUp = (event: PointerEvent) => {
      const ownUi = onOwnUi || isOwnUi(event.target);
      pointerDown = false;
      onOwnUi = false;
      if (!ownUi) schedule();
    };
    const onSelectionChange = () => {
      if (onOwnUi) return;
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !pointerDown) schedule();
    };

    document.addEventListener('selectionchange', onSelectionChange);
    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('pointerup', onPointerUp, true);
    document.addEventListener('pointercancel', onPointerUp, true);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener('selectionchange', onSelectionChange);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('pointerup', onPointerUp, true);
      document.removeEventListener('pointercancel', onPointerUp, true);
    };
  }, [enabled]);

  // スクロールしてもツールバーが選択範囲に貼りついたままになるよう、位置だけ追従させる
  const hasSelection = selection !== null;
  useEffect(() => {
    if (!hasSelection) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
        const rect = sel.getRangeAt(0).getBoundingClientRect();
        setSelection((prev) => (prev ? { ...prev, rect } : prev));
      });
    };
    window.addEventListener('scroll', onScroll, true);
    window.addEventListener('resize', onScroll);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener('scroll', onScroll, true);
      window.removeEventListener('resize', onScroll);
    };
  }, [hasSelection]);

  const dismiss = useCallback(() => {
    setSelection(null);
    window.getSelection()?.removeAllRanges();
  }, []);

  const ask = () => {
    if (!selection || !chatPanel) return;
    chatPanel.open({
      selection: buildChatSelection(
        selection.flattenedText,
        selection.startIdx,
        selection.endIdx,
        selection.text,
        screen
      ),
    });
    dismiss();
  };

  const copy = async () => {
    if (!selection) return;
    try {
      await navigator.clipboard.writeText(selection.text);
    } catch {
      /* クリップボード権限がない場合は黙って無視 */
    }
    dismiss();
  };

  // ツールバーはbodyへ出す(カードのtransform等でfixed配置がずれないように。また、
  // 領域の中に置くとtextContentに「Ask」「Copy」が混ざり、選択の前後の文字が狂う)
  return (
    <div ref={containerRef} className={className}>
      {children}
      {selection && createPortal(
        <div
          data-selection-ask-ui
          className="annotation-toolbar"
          style={floatingStyle(selection.rect, 160)}
          onMouseDown={(e) => e.preventDefault()}
        >
          <div className="annotation-toolbar-row">
            <button type="button" className="annotation-ask-btn" onClick={ask}>
              Ask
            </button>
            <button type="button" onClick={copy}>
              Copy
            </button>
          </div>
        </div>,
        document.body
      )}
    </div>
  );
};
