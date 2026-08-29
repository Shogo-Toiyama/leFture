import React from 'react';
import { useNavigate } from 'react-router-dom';
import { parseSidCitations } from '../lib/sidCitation';

interface CitationLinkProps {
  lectureId: string;
  /** ブロック内の生テキストを連結したもの。⟦...⟧が含まれていればリンクを表示する。 */
  rawText: string;
}

/**
 * review cards/deep notesの本文にSID引用が埋め込まれている場合、
 * トランスクリプトの該当箇所へジャンプするリンクを表示する。
 * モバイル版のテキスト選択→「Source」ツールバーの簡略版(read-only)。
 */
export const CitationLink: React.FC<CitationLinkProps> = ({ lectureId, rawText }) => {
  const navigate = useNavigate();
  const citations = parseSidCitations(rawText);
  if (citations.length === 0) return null;

  const allSids = Array.from(new Set(citations.flatMap((c) => c.sidStrings)));

  return (
    <button
      type="button"
      className="citation-link"
      onClick={() => navigate(`/lectures/${lectureId}/transcript?sids=${allSids.join(',')}`)}
    >
      📄 View in transcript
    </button>
  );
};
