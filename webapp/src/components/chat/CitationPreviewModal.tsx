import React, { useEffect } from 'react';
import { X, ExternalLink, ArrowRight, BookOpen, MessageSquare, Globe, Sparkles, FileText, Bell, Layers } from 'lucide-react';
import type { ChatCitation, ChatSourceType } from '../../types/chat';
import { citationRoute, citationUrl, CHAT_SOURCE_LABEL_KEYS } from '../../lib/chatCitations';
import { fixBoldPunctuationSpacing, markdownToPlainText, prepareMath } from '../../lib/markdownText';
import { useLanguage } from '../../i18n/LanguageContext';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

export interface CitationPreviewModalProps {
  citation: ChatCitation | null;
  /** 押された引用の区切り(citation.passagesのキー)。あればその区切りをハイライトして見せる。 */
  specs?: string[];
  onClose: () => void;
  onOpenFull?: (route: string) => void;
}

const SOURCE_ICONS: Record<ChatSourceType, React.ReactNode> = {
  transcript_topic: <FileText size={16} />,
  deep_note: <BookOpen size={16} />,
  review_card: <Layers size={16} />,
  announcement: <Bell size={16} />,
  keyword: <Sparkles size={16} />,
  chat_turn: <MessageSquare size={16} />,
  web: <Globe size={16} />,
  course: <BookOpen size={16} />,
  topic_summary: <BookOpen size={16} />,
  lecture_summary: <BookOpen size={16} />,
  fun_fact: <Sparkles size={16} />,
  lecture_moment: <Sparkles size={16} />,
};

export const CitationPreviewModal: React.FC<CitationPreviewModalProps> = ({
  citation,
  specs,
  onClose,
  onOpenFull,
}) => {
  const { t } = useLanguage();

  useEffect(() => {
    if (!citation) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [citation, onClose]);

  if (!citation) return null;

  const url = citationUrl(citation);
  const route = citationRoute(citation);
  const kindLabel = t(CHAT_SOURCE_LABEL_KEYS[citation.source_type]);
  const icon = SOURCE_ICONS[citation.source_type] ?? <BookOpen size={16} />;

  // ラベル分解: [Course, Lecture, Section]
  const parts = (citation.label || '').split(' / ').filter(Boolean);
  const courseOrSite = citation.source_type === 'web'
    ? (citation.metadata?.domain as string) || ''
    : parts[0] || '';
  const lectureTitle = citation.source_type === 'web'
    ? ''
    : parts[1] || '';
  const detailTitle = parts.length >= 3 ? parts.slice(2).join(' · ') : (parts[1] || citation.label);

  const handleOpenDestination = () => {
    if (url) {
      window.open(url, '_blank', 'noopener,noreferrer');
      onClose();
    } else if (route && onOpenFull) {
      onOpenFull(route);
      onClose();
    }
  };

  const sentenceRange = typeof citation.metadata?.sentence_range === 'string'
    ? citation.metadata.sentence_range
    : undefined;

  // 引用された区切り(回答役が[3.5]のように指した箇所)。無ければ従来どおり出典の抜粋を見せる
  const passages = (specs ?? [])
    .map((spec) => citation.passages?.[spec])
    .filter((p): p is NonNullable<typeof p> => !!p);

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div className="citation-modal-card" onClick={(e) => e.stopPropagation()}>
        {/* モバイル用グラブバー */}
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>

        {/* ヘッダー */}
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <div className="citation-modal-badges">
              <span className="citation-modal-badge-n">{citation.n}</span>
              <span className="citation-modal-badge-kind">
                {icon}
                <span>{kindLabel}</span>
              </span>
              {sentenceRange && (
                <span className="citation-modal-badge-meta">{sentenceRange}</span>
              )}
            </div>
            <h3 className="citation-modal-title">{detailTitle}</h3>
            {(courseOrSite || lectureTitle) && (
              <p className="citation-modal-subtitle">
                {courseOrSite}
                {courseOrSite && lectureTitle ? ' · ' : ''}
                {lectureTitle}
              </p>
            )}
          </div>
          <button
            type="button"
            className="citation-modal-close-btn"
            onClick={onClose}
            aria-label="Close"
          >
            <X size={18} />
          </button>
        </div>

        {/* 本文 (スニペット) */}
        <div className="citation-modal-body">
          {passages.length > 0 ? (
            <div className="citation-passage-list">
              {passages.map((p, i) => (
                <p key={i} className="citation-passage">
                  {p.before && <span className="citation-passage-context">{markdownToPlainText(p.before)} </span>}
                  <mark className="citation-highlight">{markdownToPlainText(p.text)}</mark>
                  {p.after && <span className="citation-passage-context"> {markdownToPlainText(p.after)}</span>}
                </p>
              ))}
            </div>
          ) : citation.snippet ? (
            <div className="citation-modal-snippet">
              <ReactMarkdown remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[rehypeKatex]}>
                {fixBoldPunctuationSpacing(prepareMath(citation.snippet))}
              </ReactMarkdown>
            </div>
          ) : (
            <div className="citation-modal-empty">
              <p>{t('chatSourcePreviewEmpty', { defaultValue: '引用箇所のテキストプレビューはありません。' })}</p>
            </div>
          )}
        </div>

        {/* フッター */}
        <div className="citation-modal-footer">
          <button type="button" className="citation-modal-btn-secondary" onClick={onClose}>
            {t('chatClose', { defaultValue: '閉じる' })}
          </button>
          {(url || route) && (
            <button
              type="button"
              className="citation-modal-btn-primary"
              onClick={handleOpenDestination}
            >
              <span>
                {url
                  ? t('chatOpenExternalWeb', { defaultValue: 'Webサイトを開く' })
                  : t('chatOpenInLecture', { defaultValue: '講義ページで全体を見る' })}
              </span>
              {url ? <ExternalLink size={15} /> : <ArrowRight size={15} />}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
