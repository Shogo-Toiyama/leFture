import React, { useEffect, useRef } from 'react';
import type { DeepNoteFigure } from '../../types/content';

interface DeepNoteFigureCardProps {
  figure: DeepNoteFigure;
  className?: string;
}

/**
 * DeepNote用の図解（HTML+SVG）カードコンポーネント。
 * Shadow DOM (attachShadow) を利用して、Claude Haikuが出力した<style>とHTML/SVGを
 * 完全カプセル化して注入する。
 * これにより:
 * 1. 外部CSSとの干渉を100%防止
 * 2. 親要素のRange.toString()やtextContentから除外され、テキストアノテーションの文字座標が狂わない
 */
export const DeepNoteFigureCard: React.FC<DeepNoteFigureCardProps> = ({ figure, className }) => {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const host = containerRef.current;
    if (!host) return;

    // Attach shadow root if not already attached
    let shadow = host.shadowRoot;
    if (!shadow) {
      shadow = host.attachShadow({ mode: 'open' });
    }

    // Set complete HTML content
    shadow.innerHTML = figure.html_content;
  }, [figure.html_content]);

  return (
    <div
      ref={containerRef}
      className={`dn-figure-host ${className ?? ''}`}
      style={{
        display: 'block',
        width: '100%',
        margin: '24px 0',
        userSelect: 'none',
      }}
      data-figure-index={figure.figure_index}
    />
  );
};
