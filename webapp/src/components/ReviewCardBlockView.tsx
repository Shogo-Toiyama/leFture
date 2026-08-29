import React from 'react';
import ReactMarkdown from 'react-markdown';
import { stripSidCitations } from '../lib/sidCitation';
import { CitationLink } from './CitationLink';
import type { ReviewCardBlock } from '../types/content';

interface ReviewCardBlockViewProps {
  block: ReviewCardBlock;
  lectureId: string;
}

function blockRawText(block: ReviewCardBlock): string {
  return [block.text, ...(block.items ?? []), block.code_string, block.explanation].filter(Boolean).join(' ');
}

export const ReviewCardBlockView: React.FC<ReviewCardBlockViewProps> = ({ block, lectureId }) => {
  const rawText = blockRawText(block);

  const body = (() => {
    switch (block.type) {
      case 'quote':
        return (
          <blockquote className="rc-block rc-block-quote">
            <ReactMarkdown>{stripSidCitations(block.text ?? '')}</ReactMarkdown>
          </blockquote>
        );
      case 'list':
        return (
          <ul className="rc-block rc-block-list">
            {(block.items ?? []).map((item, idx) => (
              <li key={idx}>
                <ReactMarkdown>{stripSidCitations(item)}</ReactMarkdown>
              </li>
            ))}
          </ul>
        );
      case 'callout':
        return (
          <div className={`rc-block rc-block-callout rc-callout-${block.alert_type ?? 'info'}`}>
            <ReactMarkdown>{stripSidCitations(block.text ?? '')}</ReactMarkdown>
          </div>
        );
      case 'code':
        return (
          <div className="rc-block rc-block-code">
            <pre>
              <code>{block.code_string}</code>
            </pre>
            {block.explanation && <p className="rc-code-explanation">{stripSidCitations(block.explanation)}</p>}
          </div>
        );
      case 'paragraph':
      default:
        return (
          <div className="rc-block rc-block-paragraph">
            <ReactMarkdown>{stripSidCitations(block.text ?? '')}</ReactMarkdown>
          </div>
        );
    }
  })();

  return (
    <div className="rc-block-wrapper">
      {body}
      <CitationLink lectureId={lectureId} rawText={rawText} />
    </div>
  );
};
