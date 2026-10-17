import React, { useEffect, useId, useRef } from 'react';
import { useAnnotationLayer } from './AnnotationContext';

interface AskOnlyRegionProps {
  className?: string;
  children: React.ReactNode;
}

/**
 * 注釈(ハイライト・ノート)を結べない領域(復習カードのコードブロックなど)を、
 * 選択→「Ask」「Copy」だけ使える領域として AnnotationLayer に登録する。
 * 登録しない領域の選択は AnnotationLayer に拾われず、ツールバーが出ない。
 */
export const AskOnlyRegion: React.FC<AskOnlyRegionProps> = ({ className, children }) => {
  const layer = useAnnotationLayer();
  const containerRef = useRef<HTMLDivElement>(null);
  const key = useId();

  useEffect(() => {
    const element = containerRef.current;
    if (!element || !layer) return;
    layer.registerBlock(key, { element, blockIdx: null, rawMarkdown: '', askOnly: true });
    return () => layer.unregisterBlock(key);
  }, [layer, key]);

  return (
    <div ref={containerRef} className={className}>
      {children}
    </div>
  );
};
