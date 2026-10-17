import React, { useLayoutEffect, useMemo, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import 'katex/dist/katex.min.css';
import { AlertCircle, ChevronDown, HeartHandshake, RotateCw } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CHAT_SOURCE_LABEL_KEYS,
  citationRef,
  citationRoute,
  citationShortLabel,
  citationUrl,
  linkifyCitations,
  parseCitationHref,
  stripCitationMarkers,
} from '../../lib/chatCitations';
import { fixBoldPunctuationSpacing, prepareMath } from '../../lib/markdownText';
import type { LocalChatMessage } from '../../hooks/useChatConversation';
import { CHAT_MAX_SELECTED_TOKENS, type ChatAttachment, type ChatAttachmentKind, type ChatCitation } from '../../types/chat';
import {
  AttachmentKindIcon,
  AttachmentStatusBadge,
  viewableFromAttachment,
  type ViewableAttachment,
} from './AttachmentViewerModal';
import { CitationPreviewModal } from './CitationPreviewModal';
import { ChatMessageActions } from './ChatMessageActions';
import { messageMentionIds, splitMessageText } from '../../lib/chatMentions';
import { useAttachmentImageUrl } from '../../hooks/useAttachmentImageUrl';

interface ChatMessageItemProps {
  message: LocalChatMessage;
  /** このメッセージで添付した資料(userのみ。サーバーの一覧から)。 */
  attachments?: ChatAttachment[];
  /** この会話の資料(外したものも含む)。本文の中のチップ・外した知らせの名前に使う。 */
  attachmentsById?: Map<string, ChatAttachment>;
  /** 資料のチップを押したとき。idは送った資料のとき(外せる)。 */
  onOpenAttachment?: (attachment: ViewableAttachment, id?: string) => void;
  /** 出典を押したとき。画面遷移は呼び出し側(パネルなら狭い画面で閉じる等)。 */
  onOpenCitation: (route: string) => void;
  /** 返答の生成に失敗したとき、直前の質問をもう一度送る。 */
  onResend?: () => void;
}

export const ChatMessageItem: React.FC<ChatMessageItemProps> = ({
  message,
  attachments,
  attachmentsById,
  onOpenAttachment,
  onOpenCitation,
  onResend,
}) => {
  if (message.role === 'user') {
    return (
      <UserMessage
        message={message}
        attachments={attachments}
        attachmentsById={attachmentsById}
        onOpenAttachment={onOpenAttachment}
      />
    );
  }
  return (
    <AssistantMessage
      message={message}
      attachmentsById={attachmentsById}
      onOpenCitation={onOpenCitation}
      onResend={onResend}
    />
  );
};

/** 送ったメッセージの資料のチップ。サーバーの一覧に載るまでは、送ったときの下書きで見せる。 */
interface AttachmentChip {
  key: string;
  title: string;
  kind: ChatAttachmentKind;
  /** 右側の小さな情報(文字数・ページ数・画像) */
  meta: string;
  status?: ChatAttachment['status'];
  /** 送った資料のとき: 全文で読ませているか */
  selected?: boolean;
  viewable: ViewableAttachment;
  id?: string;
  /** 送ったばかりの画像: 端末の小さな見本(サーバーの一覧に載るまで) */
  previewUrl?: string;
}

/** チップの左: 画像は小さな見本(どこに何を入れたかが分かるように)、それ以外は種類のアイコン。 */
const ChipIcon: React.FC<{ chip: AttachmentChip; size: number }> = ({ chip, size }) => {
  const url = useAttachmentImageUrl(chip.kind === 'image' && chip.id && chip.status === 'ready' ? chip.id : null);
  const src = url ?? chip.previewUrl;
  if (chip.kind === 'image' && src) return <img className="chat-chip-thumb" src={src} alt="" />;
  return <AttachmentKindIcon kind={chip.kind} size={size} />;
};

/** 自分のメッセージは、表示でこの行数を超えたら、先頭のこの行数だけ見せて「もっと見る」で全文にする。 */
const COLLAPSE_OVER_LINES = 10;

/**
 * 吹き出しの本文。長いときだけ折りたたむ。行数は改行の数ではなく、折り返しを含む表示の行数
 * (scrollHeight ÷ 行の高さ)で数える。幅が変わる(パネルの開閉・画面の回転)たびに数え直す。
 */
const CollapsibleBubbleText: React.FC<{ contentKey: string; children: React.ReactNode }> = ({
  contentKey,
  children,
}) => {
  const { t } = useLanguage();
  const ref = useRef<HTMLParagraphElement>(null);
  const [overflowing, setOverflowing] = useState(false);
  const [expanded, setExpanded] = useState(false);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const style = getComputedStyle(el);
      const lineHeight = parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.6;
      setOverflowing(el.scrollHeight / lineHeight > COLLAPSE_OVER_LINES + 0.5);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, [contentKey]);

  const collapsed = overflowing && !expanded;
  return (
    <>
      <p ref={ref} className={`chat-bubble-text ${collapsed ? 'is-collapsed' : ''}`}>
        {children}
      </p>
      {overflowing && (
        <button
          type="button"
          className="chat-bubble-more"
          aria-expanded={expanded}
          onClick={() => setExpanded((open) => !open)}
        >
          {expanded ? t('chatShowLess') : t('chatShowMore')}
          <ChevronDown size={13} className={expanded ? 'is-open' : ''} />
        </button>
      )}
    </>
  );
};

const UserMessage: React.FC<{
  message: LocalChatMessage;
  attachments?: ChatAttachment[];
  attachmentsById?: Map<string, ChatAttachment>;
  onOpenAttachment?: (attachment: ViewableAttachment, id?: string) => void;
}> = ({ message, attachments, attachmentsById, onOpenAttachment }) => {
  const { t, formatNumber } = useLanguage();
  const selected = message.context?.selected_text;
  const metaFor = (kind: ChatAttachmentKind, chars: number, pages: number | null | undefined) => {
    if (kind === 'image') return t('chatFileImage');
    if (kind === 'pdf' && pages) return t('chatFilePages', { count: pages });
    if (kind === 'pptx' && pages) return t('chatFileSlides', { count: pages });
    return t('chatAttachmentChars', { count: formatNumber(chars) });
  };
  const allChips: AttachmentChip[] = attachments?.length
    ? attachments.map((a) => ({
        key: a.id,
        title: a.title || a.file_name || t('chatAttachmentUntitled'),
        kind: a.kind,
        meta: metaFor(a.kind, a.char_count, a.page_count),
        status: a.status,
        selected: a.selected,
        viewable: viewableFromAttachment(a),
        id: a.id,
      }))
    : (message.localAttachments ?? []).map((d) =>
        d.kind === 'file'
          ? {
              key: d.localId,
              title: d.fileName,
              kind: d.fileKind,
              meta: metaFor(d.fileKind, d.info?.text_chars ?? 0, d.info?.page_count),
              viewable: { title: d.fileName, content: '', kind: d.fileKind, status: 'processing' as const },
              previewUrl: d.previewUrl,
            }
          : {
              key: d.localId,
              title:
                d.title || d.content.split('\n').find((line) => line.trim())?.trim() || t('chatAttachmentUntitled'),
              kind: 'text' as const,
              meta: t('chatAttachmentChars', { count: formatNumber(d.content.length) }),
              viewable: { title: d.title || null, content: d.content },
            }
      );
  // 本文の中で指している資料はその位置のチップで見せるので、上には出さない(指していない添付だけ上に出す)
  const inlineIds = new Set(messageMentionIds(message.content));
  const localIdOf = (chip: AttachmentChip) => {
    const d = message.localAttachments?.find((x) => x.localId === chip.key);
    return d?.kind === 'file' ? d.attachmentId : d?.localId;
  };
  const chips = allChips.filter((chip) => !inlineIds.has(chip.id ?? '') && !inlineIds.has(localIdOf(chip) ?? ''));
  const modeOf = (id: string) => message.context?.attachments?.find((a) => a.id === id)?.mode;
  /** 本文の印 → チップの中身(サーバーの一覧 → 送ったときの下書き の順に探す) */
  const inlineChip = (id: string): AttachmentChip | null => {
    const a = attachmentsById?.get(id);
    if (a) return allChips.find((c) => c.id === id) ?? {
      key: a.id,
      title: a.title || a.file_name || t('chatAttachmentUntitled'),
      kind: a.kind,
      meta: '',
      status: a.status,
      selected: a.selected,
      viewable: viewableFromAttachment(a),
      id: a.id,
    };
    return allChips.find((c) => localIdOf(c) === id) ?? null;
  };
  // コピーする本文: 資料の印(⟦att:…⟧)は資料の名前に直す
  const copyText = splitMessageText(message.content)
    .map((part) =>
      part.type === 'text' ? part.text : (inlineChip(part.id)?.title ?? t('chatMentionRemoved'))
    )
    .join('');
  return (
    <div className={`chat-msg is-user ${message.failedCode ? 'is-failed' : ''}`}>
      {chips.length > 0 && (
        <div className="chat-msg-attachments">
          {chips.map((chip) => (
            <button
              key={chip.key}
              type="button"
              className={`chat-msg-attachment ${chip.status && chip.status !== 'ready' ? `is-${chip.status}` : ''}`}
              onClick={() => onOpenAttachment?.(chip.viewable, chip.id)}
              title={chip.title}
            >
              <ChipIcon chip={chip} size={13} />
              <span className="chat-msg-attachment-title">{chip.title}</span>
              <span className="chat-msg-attachment-meta">{chip.meta}</span>
              {chip.status === 'ready' && chip.selected && (
                <span className="chat-attachment-mode is-full">{t('chatAttachPinned')}</span>
              )}
              {chip.status && <AttachmentStatusBadge status={chip.status} />}
            </button>
          ))}
        </div>
      )}
      {(message.content || selected) && (
        <div className="chat-bubble">
          {selected && <blockquote className="chat-bubble-quote">{selected}</blockquote>}
          {message.content && (
            <CollapsibleBubbleText contentKey={message.content}>
              {splitMessageText(message.content).map((part, i) => {
                if (part.type === 'text') return <React.Fragment key={i}>{part.text}</React.Fragment>;
                const chip = inlineChip(part.id);
                if (!chip) {
                  return (
                    <span key={i} className="chat-inline-mention is-removed">
                      {t('chatMentionRemoved')}
                    </span>
                  );
                }
                const full = modeOf(part.id) === 'full';
                return (
                  <button
                    key={i}
                    type="button"
                    className={`chat-inline-mention ${full ? 'is-full' : ''} ${chip.status && chip.status !== 'ready' ? `is-${chip.status}` : ''}`}
                    onClick={() => onOpenAttachment?.(chip.viewable, chip.id)}
                    title={full ? `${chip.title}(${t('chatAttachFull')})` : chip.title}
                  >
                    <ChipIcon chip={chip} size={12} />
                    <span className="chat-inline-mention-title">{chip.title}</span>
                    {full && <span className="chat-inline-mention-mode">{t('chatMentionFullTag')}</span>}
                    {chip.status && chip.status !== 'ready' && <AttachmentStatusBadge status={chip.status} />}
                  </button>
                );
              })}
            </CollapsibleBubbleText>
          )}
        </div>
      )}
      {message.content && <ChatMessageActions copyText={copyText} />}
      {message.failedCode && (
        <span className="chat-msg-failed">
          <AlertCircle size={13} />
          {t('chatNotSent')}
        </span>
      )}
    </div>
  );
};

// 回答本文のMarkdown: GFM(表など)と数式(KaTeX)
const MARKDOWN_REMARK_PLUGINS = [remarkGfm, remarkMath];
const MARKDOWN_REHYPE_PLUGINS = [rehypeKatex];

function canOpenCitation(citation: ChatCitation | undefined): boolean {
  return (
    !!citation &&
    (citationUrl(citation) !== null || citationRoute(citation) !== null || !!citation.snippet || !!citation.passages)
  );
}

/** 開いている出典のプレビュー。specs は押された引用の区切り(無ければ出典全体の表示)。 */
interface PreviewState {
  citation: ChatCitation;
  specs?: string[];
}

/** 全文で読む枠を超えて外した資料・長すぎて全文にできなかった資料の知らせ(返答の下)。 */
const AttachmentNotice: React.FC<{ message: LocalChatMessage; attachmentsById?: Map<string, ChatAttachment> }> = ({
  message,
  attachmentsById,
}) => {
  const { t } = useLanguage();
  const notice = message.context?.attachment_notice;
  if (!notice || (!notice.unpinned?.length && !notice.too_long?.length)) return null;
  const names = (ids: string[]) =>
    ids
      .map((id) => {
        const a = attachmentsById?.get(id);
        return `「${a?.title || a?.file_name || t('chatAttachmentUntitled')}」`;
      })
      .join('');
  return (
    <div className="chat-attachment-notice" role="note">
      {notice.unpinned?.length > 0 && (
        <p>{t('chatNoticeUnpinned', { titles: names(notice.unpinned), max: CHAT_MAX_SELECTED_TOKENS.toLocaleString() })}</p>
      )}
      {notice.too_long?.length > 0 && <p>{t('chatNoticeTooLong', { titles: names(notice.too_long) })}</p>}
    </div>
  );
};

const AssistantMessage: React.FC<{
  message: LocalChatMessage;
  attachmentsById?: Map<string, ChatAttachment>;
  onOpenCitation: (route: string) => void;
  onResend?: () => void;
}> = ({ message, attachmentsById, onOpenCitation, onResend }) => {
  const { t } = useLanguage();
  const [preview, setPreview] = useState<PreviewState | null>(null);

  // 生成中は出典の候補(pendingSources)、完了後は本文で実際に使われた出典(citations)
  // で番号を引く。番号は講義・チャットが "1", "2"…、Webのページが "W1", "W2"…。
  const byRef = useMemo(() => {
    const map = new Map<string, ChatCitation>();
    for (const c of message.pendingSources ?? []) map.set(citationRef(c), c);
    for (const c of message.citations ?? []) map.set(citationRef(c), c);
    return map;
  }, [message.pendingSources, message.citations]);
  const refs = useMemo(() => new Set(byRef.keys()), [byRef]);

  // 数式(LaTeX)をremark-mathが読める形にそろえてから、引用をリンクにし、太字を直す(どちらも数式の中は触らない)
  const markdown = useMemo(
    () => fixBoldPunctuationSpacing(linkifyCitations(prepareMath(message.content), refs)),
    [message.content, refs]
  );

  // コピーは出典の印だけ取り除いた元のMarkdown(prepareMath等で整形する前のもの)
  const copyText = useMemo(() => stripCitationMarkers(message.content, refs).trim(), [message.content, refs]);

  if (message.status === 'crisis') {
    return (
      <div className="chat-msg is-assistant">
        <div className="chat-care" role="note">
          <HeartHandshake size={18} className="chat-care-icon" />
          <div className="chat-markdown">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{fixBoldPunctuationSpacing(message.content)}</ReactMarkdown>
          </div>
        </div>
      </div>
    );
  }

  const isGenerating = message.status === 'streaming';
  const showStage = isGenerating && !message.content;
  // 探しているものが複数なら、Web → 過去のチャット → 講義の順に1つだけ出す
  const detail = message.searchDetail ?? [];
  const query = message.searchQuery?.trim();
  const truncatedQuery = query ? (query.length > 25 ? `${query.slice(0, 24)}…` : query) : undefined;

  let stageLabel = t('chatStageThinking');
  if (message.stage === 'reading_attachments') {
    stageLabel = t('chatStageReadingAttachments');
  } else if (message.stage === 'searching') {
    if (message.searchTarget === 'attachments' || detail.includes('attachments')) {
      stageLabel = t('chatStageReadingAttachment');
    } else if (message.searchTarget === 'web' || detail.includes('web')) {
      stageLabel = truncatedQuery
        ? t('chatStageSearchingWebWithQuery', { query: truncatedQuery })
        : t('chatStageSearchingWeb');
    } else if (message.searchTarget === 'chats' || detail.includes('chats')) {
      stageLabel = truncatedQuery
        ? t('chatStageSearchingChatsWithQuery', { query: truncatedQuery })
        : t('chatStageSearchingChats');
    } else if (message.searchLayer === 'transcript') {
      stageLabel = truncatedQuery
        ? t('chatStageSearchingTranscriptWithQuery', { query: truncatedQuery })
        : t('chatStageReadingTranscript');
    } else if (truncatedQuery) {
      stageLabel = t('chatStageSearchingNotesWithQuery', { query: truncatedQuery });
    } else if (message.searchHandle) {
      stageLabel = message.searchHandle.includes('/s')
        ? t('chatStageReadingTranscript')
        : t('chatStageReadingNotes');
    } else {
      stageLabel = t('chatStageSearching');
    }
  } else if (message.stage === 'reasoning') {
    stageLabel = t('chatStageReasoning');
  } else if (message.stage === 'writing') {
    stageLabel = t('chatStageWriting');
  }

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
            remarkPlugins={MARKDOWN_REMARK_PLUGINS}
            rehypePlugins={MARKDOWN_REHYPE_PLUGINS}
            components={{
              a: ({ href, children }) => {
                const parsed = parseCitationHref(href);
                if (parsed !== null) {
                  const { ref, specs } = parsed;
                  const citation = byRef.get(ref);
                  return (
                    <button
                      type="button"
                      className="chat-cite-marker"
                      title={citation?.label}
                      disabled={!canOpenCitation(citation)}
                      // 押した引用の区切りをハイライトして見せる
                      onClick={() => citation && setPreview({ citation, specs })}
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

      <AttachmentNotice message={message} attachmentsById={attachmentsById} />

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
                // チップはその出典の引用された区切りを全部見せる
                onClick={() => setPreview({ citation, specs: Object.keys(citation.passages ?? {}) })}
              >
                <span className="chat-cite-chip-n">{citation.n}</span>
                <span className="chat-cite-chip-kind">{t(CHAT_SOURCE_LABEL_KEYS[citation.source_type])}</span>
                <span className="chat-cite-chip-label">{citationShortLabel(citation)}</span>
              </button>
            );
          })}
        </div>
      )}

      {message.status === 'complete' && <ChatMessageActions copyText={copyText} detailsFor={message} />}

      <CitationPreviewModal
        citation={preview?.citation ?? null}
        specs={preview?.specs}
        onClose={() => setPreview(null)}
        onOpenFull={onOpenCitation}
      />
    </div>
  );
};
