import React, { useEffect, useId, useMemo, useRef } from 'react';
import ReactMarkdown, { defaultUrlTransform } from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import 'katex/dist/katex.min.css';
import { prepareMath, remarkBracketEmphasis } from '../../lib/markdownText';
import { rehypeAnnotations } from '../../lib/markdownAnnotations';
import { useAnnotationLayer } from './AnnotationContext';
import type { Annotation } from '../../types/annotation';
import type { DeepNoteFigure } from '../../types/content';
import { DeepNoteFigureCard } from '../deepNotes/DeepNoteFigureCard';

interface AnnotatedMarkdownProps {
  /** SID引用・FIGUREプレースホルダーを除去または変換済みのMarkdown。 */
  markdown: string;
  /** 引用マーカーを含む生Markdown ("Source"アクション用)。 */
  rawMarkdown: string;
  annotations: Annotation[];
  /** ReviewCardのブロックindex。DeepNotesはnull。 */
  blockIdx: number | null;
  className?: string;
  figures?: DeepNoteFigure[];
}

export const AnnotatedMarkdown: React.FC<AnnotatedMarkdownProps> = ({
  markdown,
  rawMarkdown,
  annotations,
  blockIdx,
  className,
  figures,
}) => {
  const layer = useAnnotationLayer();
  const containerRef = useRef<HTMLDivElement>(null);
  const key = useId();

  useEffect(() => {
    const element = containerRef.current;
    if (!element || !layer) return;
    layer.registerBlock(key, { element, blockIdx, rawMarkdown });
    return () => layer.unregisterBlock(key);
  }, [layer, key, blockIdx, rawMarkdown]);

  const preparedMarkdown = useMemo(() => prepareMath(markdown), [markdown]);
  const remarkPlugins = useMemo(() => [remarkGfm, remarkMath, remarkBracketEmphasis], []);
  const rehypePlugins = useMemo(() => [rehypeAnnotations(annotations), rehypeKatex], [annotations]);

  const urlTransform = useMemo(
    () => (url: string) => (url.startsWith('figure:') ? url : defaultUrlTransform(url)),
    []
  );

  const components = useMemo(
    () => ({
      img: ({ src, alt, ...props }: React.ComponentPropsWithoutRef<'img'>) => {
        if (src?.startsWith('figure:')) {
          const idx = Number(src.replace('figure:', ''));
          const fig = figures?.find((f) => f.figure_index === idx);
          if (fig) {
            return <DeepNoteFigureCard figure={fig} />;
          }
          return null;
        }
        return <img src={src} alt={alt} {...props} />;
      },
    }),
    [figures]
  );

  const handleClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!layer) return;
    const target = (event.target as HTMLElement).closest('[data-annotation-id]');
    if (!target) return;
    const annotationId = target.getAttribute('data-annotation-id');
    if (!annotationId) return;
    event.stopPropagation();
    layer.openAnnotation(annotationId, target.getBoundingClientRect());
  };

  return (
    <div ref={containerRef} className={className} onClick={handleClick}>
      <ReactMarkdown
        remarkPlugins={remarkPlugins}
        rehypePlugins={rehypePlugins}
        components={components}
        urlTransform={urlTransform}
      >
        {preparedMarkdown}
      </ReactMarkdown>
    </div>
  );
};

