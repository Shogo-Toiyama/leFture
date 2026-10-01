import React, { useMemo } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { AlertCircle, HeartHandshake, RotateCw } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CHAT_SOURCE_LABEL_KEYS,
  citationRef,
  citationRoute,
  citationShortLabel,
  citationUrl,
  linkifyCitations,
  parseCitationHref,
} from '../../lib/chatCitations';
import type { LocalChatMessage } from '../../hooks/useChatConversation';
import type { ChatCitation } from '../../types/chat';

interface ChatMessageItemProps {
  message: LocalChatMessage;
  /** 出典を押したとき。画面遷移は呼び出し側(パネルなら狭い画面で閉じる等)。 */
  onOpenCitation: (route: string) => void;
  /** 返答の生成に失敗したとき、直前の質問をもう一度送る。 */
  onResend?: () => void;
}

export const ChatMessageItem: React.FC<ChatMessageItemProps> = ({ message, onOpenCitation, onResend }) => {
  if (message.role === 'user') return <UserMessage message={message} />;
  return <AssistantMessage message={message} onOpenCitation={onOpenCitation} onResend={onResend} />;
};

const UserMessage: React.FC<{ message: LocalChatMessage }> = ({ message }) => {
  const { t } = useLanguage();
  const selected = message.context?.selected_text;
  return (
    <div className={`chat-msg is-user ${message.failedCode ? 'is-failed' : ''}`}>
      <div className="chat-bubble">
        {selected && <blockquote className="chat-bubble-quote">{selected}</blockquote>}
        <p className="chat-bubble-text">{message.content}</p>
      </div>
      {message.failedCode && (
        <span className="chat-msg-failed">
          <AlertCircle size={13} />
          {t('chatNotSent')}
        </span>
      )}
    </div>
  );
};

/** 出典を開く: Webのページは新しいタブで元のページ、それ以外はアプリ内の画面。 */
function openCitation(citation: ChatCitation, onOpenCitation: (route: string) => void): void {
  const url = citationUrl(citation);
  if (url) {
    window.open(url, '_blank', 'noopener,noreferrer');
    return;
  }
  const route = citationRoute(citation);
  if (route) onOpenCitation(route);
}

function canOpenCitation(citation: ChatCitation | undefined): boolean {
  return !!citation && (citationUrl(citation) !== null || citationRoute(citation) !== null);
}

const AssistantMessage: React.FC<{
  message: LocalChatMessage;
  onOpenCitation: (route: string) => void;
  onResend?: () => void;
}> = ({ message, onOpenCitation, onResend }) => {
  const { t, formatNumber } = useLanguage();

  // 生成中は出典の候補(pendingSources)、完了後は本文で実際に使われた出典(citations)
  // で番号を引く。番号は講義・チャットが "1", "2"…、Webのページが "W1", "W2"…。
  const byRef = useMemo(() => {
    const map = new Map<string, ChatCitation>();
    for (const c of message.pendingSources ?? []) map.set(citationRef(c), c);
    for (const c of message.citations ?? []) map.set(citationRef(c), c);
    return map;
  }, [message.pendingSources, message.citations]);
  const refs = useMemo(() => new Set(byRef.keys()), [byRef]);

  const markdown = useMemo(() => linkifyCitations(message.content, refs), [message.content, refs]);

  if (message.status === 'crisis') {
    return (
      <div className="chat-msg is-assistant">
        <div className="chat-care" role="note">
          <HeartHandshake size={18} className="chat-care-icon" />
          <div className="chat-markdown">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{message.content}</ReactMarkdown>
          </div>
        </div>
      </div>
    );
  }

  const isGenerating = message.status === 'streaming';
  const showStage = isGenerating && !message.content;
  // 探しているものが複数なら、Web → 過去のチャット → 講義の順に1つだけ出す
  const detail = message.searchDetail ?? [];
  const stageLabel =
    message.stage === 'searching'
      ? detail.includes('web')
        ? t('chatStageSearchingWeb')
        : detail.includes('chats')
          ? t('chatStageSearchingChats')
          : t('chatStageSearching')
      : message.stage === 'writing'
        ? t('chatStageWriting')
        : t('chatStageThinking');
  const credits = (message.credits_charged_micro ?? 0) / 1_000_000;

  return (
    <div className={`chat-msg is-assistant ${message.status === 'blocked' ? 'is-blocked' : ''}`}>
      {showStage && !message.reconnecting && (
        <span className="chat-stage" aria-live="polite">
          <span className="chat-dots" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          {stageLabel}
        </span>
      )}

      {message.content && (
        <div className={`chat-markdown ${isGenerating ? 'is-streaming' : ''}`}>
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              a: ({ href, children }) => {
                const ref = parseCitationHref(href);
                if (ref !== null) {
                  const citation = byRef.get(ref);
                  return (
                    <button
                      type="button"
                      className="chat-cite-marker"
                      title={citation?.label}
                      disabled={!canOpenCitation(citation)}
                      onClick={() => citation && openCitation(citation, onOpenCitation)}
                    >
                      {ref}
                    </button>
                  );
                }
                return (
                  <a href={href} target="_blank" rel="noreferrer">
                    {children}
                  </a>
                );
              },
            }}
          >
            {markdown}
          </ReactMarkdown>
        </div>
      )}

      {message.reconnecting && (
        <span className="chat-stage">
          <span className="chat-dots" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          {t('chatReconnecting')}
        </span>
      )}

      {message.status === 'error' && (
        <div className="chat-inline-error" role="alert">
          <span>{t('chatReplyFailed')}</span>
          {onResend && (
            <button type="button" className="chat-link-btn" onClick={onResend}>
              <RotateCw size={13} />
              {t('chatResend')}
            </button>
          )}
        </div>
      )}

      {message.status === 'complete' && message.citations.length > 0 && (
        <div className="chat-citations" aria-label={t('chatSourcesLabel')}>
          {message.citations.map((citation) => {
            return (
              <button
                key={citationRef(citation)}
                type="button"
                className="chat-cite-chip"
                disabled={!canOpenCitation(citation)}
                title={citation.url ? `${citation.label}\n${citation.url}` : citation.label}
                onClick={() => openCitation(citation, onOpenCitation)}
              >
                <span className="chat-cite-chip-n">{citation.n}</span>
                <span className="chat-cite-chip-kind">{t(CHAT_SOURCE_LABEL_KEYS[citation.source_type])}</span>
                <span className="chat-cite-chip-label">{citationShortLabel(citation)}</span>
              </button>
            );
          })}
        </div>
      )}

      {message.status === 'complete' && credits > 0 && (
        <span className="chat-msg-meta">
          {t('chatCreditsUsed', { credits: formatNumber(credits, { maximumFractionDigits: 1 }) })}
        </span>
      )}
    </div>
  );
};
