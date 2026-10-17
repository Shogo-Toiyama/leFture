import React, { useMemo } from 'react';
import katex from 'katex';
import 'katex/dist/katex.min.css';
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
      <p className="rc-code-explanation">{stripSidCitations(block.explanation)}</p>
    );
    // 数式(KaTeXの出力)はtextContentにMathMLの複製が混ざり、選択の文字列が崩れるので選択の対象にしない。
    // 注釈(ハイライト等)は結べないので、コードと説明文は「Ask」「Copy」だけの領域にする。
    if (block.language?.toLowerCase() === 'latex') {
      return (
        <div className="rc-block rc-block-code">
          <LatexBlock source={block.code_string ?? ''} />
          {explanation && <AskOnlyRegion>{explanation}</AskOnlyRegion>}
        </div>
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
