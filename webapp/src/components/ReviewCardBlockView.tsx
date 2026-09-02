import React from 'react';
import { AnnotatedMarkdown } from './annotations/AnnotatedMarkdown';
import { blockMarkdownSource, blockRawMarkdownSource, isAnnotatableBlock } from '../lib/reviewCardBlocks';
import { stripSidCitations } from '../lib/sidCitation';
import { annotationsForBlock } from '../lib/annotations';
import type { Annotation } from '../types/annotation';
import type { ReviewCardBlock } from '../types/content';

interface ReviewCardBlockViewProps {
  block: ReviewCardBlock;
  blockIdx: number;
  annotations: Annotation[];
}

const WRAPPER_CLASS: Record<string, string> = {
  quote: 'rc-block rc-block-quote',
  list: 'rc-block rc-block-list',
  paragraph: 'rc-block rc-block-paragraph',
};

export const ReviewCardBlockView: React.FC<ReviewCardBlockViewProps> = ({
  block,
  blockIdx,
  annotations,
}) => {
  if (block.type === 'code') {
    return (
      <div className="rc-block rc-block-code">
        <pre>
          <code>{block.code_string}</code>
        </pre>
        {block.explanation && <p className="rc-code-explanation">{stripSidCitations(block.explanation)}</p>}
      </div>
    );
  }

  const className =
    block.type === 'callout'
      ? `rc-block rc-block-callout rc-callout-${block.alert_type ?? 'info'}`
      : WRAPPER_CLASS[block.type] ?? 'rc-block rc-block-paragraph';

  if (!isAnnotatableBlock(block)) {
    return null;
  }

  return (
    <AnnotatedMarkdown
      className={className}
      markdown={blockMarkdownSource(block)}
      rawMarkdown={blockRawMarkdownSource(block)}
      annotations={annotationsForBlock(annotations, blockIdx)}
      blockIdx={blockIdx}
    />
  );
};
