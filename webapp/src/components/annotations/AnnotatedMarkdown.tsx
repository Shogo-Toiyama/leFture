import React, { useEffect, useId, useMemo, useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { rehypeAnnotations } from '../../lib/markdownAnnotations';
import { useAnnotationLayer } from './AnnotationContext';
import type { Annotation } from '../../types/annotation';

interface AnnotatedMarkdownProps {
  /** SID引用・FIGUREプレースホルダーを除去済みのMarkdown。 */
  markdown: string;
  /** 引用マーカーを含む生Markdown ("Source"アクション用)。 */
  rawMarkdown: string;
  annotations: Annotation[];
  /** ReviewCardのブロックindex。DeepNotesはnull。 */
  blockIdx: number | null;
  className?: string;
}

export const AnnotatedMarkdown: React.FC<AnnotatedMarkdownProps> = ({
  markdown,
  rawMarkdown,
  annotations,
  blockIdx,
  className,
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

  const rehypePlugins = useMemo(() => [rehypeAnnotations(annotations)], [annotations]);

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
      <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={rehypePlugins}>
        {markdown}
      </ReactMarkdown>
    </div>
  );
};
