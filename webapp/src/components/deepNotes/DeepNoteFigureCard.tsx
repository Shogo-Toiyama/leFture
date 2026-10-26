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
 * ルート要素には `span (display: block)` を採用し、ReactMarkdown の `<p>` 内に
 * レンダリングされても HTML 仕様のネスト違反 (p > div) によるクラッシュを防止する。
 */
export const DeepNoteFigureCard: React.FC<DeepNoteFigureCardProps> = ({ figure, className }) => {
  const containerRef = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const host = containerRef.current;
    if (!host) return;

    try {
      let shadow = host.shadowRoot;
      if (!shadow) {
        shadow = host.attachShadow({ mode: 'open' });
      }
      shadow.innerHTML = figure.html_content;
    } catch (e) {
      console.error('[DeepNoteFigureCard] Shadow DOM injection failed:', e);
    }
  }, [figure.html_content]);

  return (
    <span
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
