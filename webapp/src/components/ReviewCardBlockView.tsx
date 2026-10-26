import React, { useMemo } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import katex from 'katex';
import 'katex/dist/katex.min.css';
import { prepareMath } from '../lib/markdownText';
import { AnnotatedMarkdown } from './annotations/AnnotatedMarkdown';
import { AskOnlyRegion } from './annotations/AskOnlyRegion';
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
    const explanation = block.explanation && (
      <div className="rc-code-explanation rcv-code-explanation">
        <ReactMarkdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[rehypeKatex]}>
          {prepareMath(stripSidCitations(block.explanation))}
        </ReactMarkdown>
      </div>
    );
    // 数式ブロックおよび説明文は「Ask」「Copy」の対象領域として登録する
    if (block.language?.toLowerCase() === 'latex') {
      return (
        <AskOnlyRegion className="rc-block rc-block-code">
          <LatexBlock source={block.code_string ?? ''} />
          {explanation}
        </AskOnlyRegion>
      );
    }
    return (
      <AskOnlyRegion className="rc-block rc-block-code">
        <pre>
          <code>{block.code_string}</code>
        </pre>
        {explanation}
      </AskOnlyRegion>
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

/**
 * 復習カードの数式ブロック(生成プロンプトが「数式はLaTeXで」と指示し、language: "latex" のcodeブロックで届く)。
 * 読めないLaTeXでも画面を壊さないよう throwOnError: false(その部分だけ赤字で元の式を出す)。
 * KaTeXの出力はKaTeX自身がエスケープしたHTML(trust: false のまま。\\href等は描かない)。
 */
const LatexBlock: React.FC<{ source: string }> = ({ source }) => {
  const html = useMemo(
    () => katex.renderToString(source, { displayMode: true, throwOnError: false }),
    [source]
  );
  return <div className="rc-latex" dangerouslySetInnerHTML={{ __html: html }} />;
};
