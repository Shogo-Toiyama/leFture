import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { buildTermGlossary, type TermEntry, type TermGlossary } from '../../lib/termGlossary';
import { useLanguage } from '../../i18n/LanguageContext';
import type { Keyword } from '../../types/content';

interface TermGlossaryValue {
  glossary: TermGlossary;
  topicNumber: number | null;
}

const TermGlossaryContext = createContext<TermGlossaryValue | null>(null);

export function useTermGlossary(): TermGlossaryValue | null {
  return useContext(TermGlossaryContext);
}

interface OpenTerm {
  entry: TermEntry;
  rect: DOMRect;
  /** クリック/タップで開いたもの。ホバーが外れても閉じない。 */
  pinned: boolean;
}

const HOVER_OPEN_DELAY = 250;
const HOVER_CLOSE_DELAY = 180;

function termTarget(event: { target: EventTarget | null }): HTMLElement | null {
  const el = event.target instanceof Element ? event.target : null;
  return (el?.closest('[data-term-id]') as HTMLElement | null) ?? null;
}

function hasTextSelection(): boolean {
  const selection = window.getSelection();
  return Boolean(selection && !selection.isCollapsed);
}

interface TermGlossaryProviderProps {
  keywords: Keyword[];
  /** いま表示しているトピック。表記が重なったときにこのトピックのキーワードを優先する。 */
  topicNumber: number | null;
  children: React.ReactNode;
}

/**
 * 本文中の用語マーク(.term-mark)にホバー(マウス)またはタップ(タッチ)で
 * 定義のポップオーバーを出す。マーク自体はAnnotatedMarkdownがrehypeTermMarksで付ける。
 */
export const TermGlossaryProvider: React.FC<TermGlossaryProviderProps> = ({
  keywords,
  topicNumber,
  children,
}) => {
  const glossary = useMemo(() => buildTermGlossary(keywords), [keywords]);
  const value = useMemo(() => ({ glossary, topicNumber }), [glossary, topicNumber]);
  const [open, setOpen] = useState<OpenTerm | null>(null);
  const openTimer = useRef<number | null>(null);
  const closeTimer = useRef<number | null>(null);

  const clearTimers = useCallback(() => {
    if (openTimer.current !== null) window.clearTimeout(openTimer.current);
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
    openTimer.current = null;
    closeTimer.current = null;
  }, []);

  useEffect(() => clearTimers, [clearTimers]);

  const scheduleClose = useCallback(() => {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
    closeTimer.current = window.setTimeout(() => {
      setOpen((current) => (current?.pinned ? current : null));
    }, HOVER_CLOSE_DELAY);
  }, []);

  const handlePointerOver = (event: React.PointerEvent) => {
    if (event.pointerType !== 'mouse') return;
    const target = termTarget(event);
    if (!target) return;
    const entry = glossary.entries.get(target.dataset.termId ?? '');
    if (!entry) return;
    clearTimers();
    openTimer.current = window.setTimeout(() => {
      if (hasTextSelection()) return; // 選択中にポップアップを出すとハイライト操作の邪魔になる
      setOpen((current) =>
        current?.pinned ? current : { entry, rect: target.getBoundingClientRect(), pinned: false }
      );
    }, HOVER_OPEN_DELAY);
  };

  const handlePointerOut = (event: React.PointerEvent) => {
    if (event.pointerType !== 'mouse' || !termTarget(event)) return;
    if (openTimer.current !== null) window.clearTimeout(openTimer.current);
    openTimer.current = null;
    scheduleClose();
  };

  const handleClick = (event: React.MouseEvent) => {
    const target = termTarget(event);
    // アノテーションの上をクリックした場合は、AnnotatedMarkdownがstopPropagationするのでここに来ない
    if (!target || hasTextSelection()) return;
    const entry = glossary.entries.get(target.dataset.termId ?? '');
    if (!entry) return;
    clearTimers();
    setOpen({ entry, rect: target.getBoundingClientRect(), pinned: true });
  };

  return (
    <TermGlossaryContext.Provider value={value}>
      <div
        className="term-glossary-scope"
        onPointerOver={handlePointerOver}
        onPointerOut={handlePointerOut}
        onClick={handleClick}
      >
        {children}
      </div>
      {open && (
        <TermPopover
          open={open}
          onClose={() => setOpen(null)}
          onHoverKeep={clearTimers}
          onHoverLeave={scheduleClose}
        />
      )}
    </TermGlossaryContext.Provider>
  );
};

const POPOVER_WIDTH = 320;
const GUTTER = 12;

const TermPopover: React.FC<{
  open: OpenTerm;
  onClose: () => void;
  onHoverKeep: () => void;
  onHoverLeave: () => void;
}> = ({ open, onClose, onHoverKeep, onHoverLeave }) => {
  const { t } = useLanguage();
  const ref = useRef<HTMLDivElement>(null);
  const [placeAbove, setPlaceAbove] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    const onDown = (e: PointerEvent) => {
      const target = e.target instanceof Element ? e.target : null;
      if (ref.current?.contains(target)) return;
      if (target?.closest('[data-term-id]')) return; // 別の用語へのタップは onClick が切り替える
      onClose();
    };
    // スクロールするとマークの位置からずれるので閉じる
    const onScroll = () => onClose();
    window.addEventListener('keydown', onKey);
    window.addEventListener('pointerdown', onDown, true);
    window.addEventListener('scroll', onScroll, true);
    window.addEventListener('resize', onScroll);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('pointerdown', onDown, true);
      window.removeEventListener('scroll', onScroll, true);
      window.removeEventListener('resize', onScroll);
    };
  }, [onClose]);

  // 下に入りきらなければマークの上に出す
  useEffect(() => {
    const height = ref.current?.offsetHeight ?? 0;
    setPlaceAbove(open.rect.bottom + 8 + height > window.innerHeight - GUTTER && open.rect.top - 8 - height > GUTTER);
  }, [open]);

  const width = Math.min(POPOVER_WIDTH, window.innerWidth - GUTTER * 2);
  const left = Math.min(
    Math.max(GUTTER, open.rect.left + open.rect.width / 2 - width / 2),
    window.innerWidth - width - GUTTER
  );
  const style: React.CSSProperties = placeAbove
    ? { left, width, bottom: window.innerHeight - open.rect.top + 8 }
    : { left, width, top: open.rect.bottom + 8 };

  return createPortal(
    <div
      ref={ref}
      className="term-popover"
      style={style}
      role="dialog"
      aria-label={open.entry.keyword}
      onPointerEnter={onHoverKeep}
      onPointerLeave={(e) => {
        if (e.pointerType === 'mouse' && !open.pinned) onHoverLeave();
      }}
    >
      <div className="term-popover-label">{t('termPopoverLabel')}</div>
      <div className="term-popover-title">{open.entry.keyword}</div>
      <p className="term-popover-definition">{open.entry.definition}</p>
    </div>,
    document.body
  );
};
