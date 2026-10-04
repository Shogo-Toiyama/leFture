/**
 * 横断チャットボット(段階1 MVP)の型。
 * バックエンド: lefture_backend/app/services/chat_service.py / main.pyの /chat/*
 * DB: chat_threads / chat_messages (本人のみSELECT可。書き込みはバックエンド経由のみ)
 */

export type ChatMessageRole = 'user' | 'assistant';

/**
 * streaming: 生成中 / complete: 完了 / error: 失敗(課金なし)
 * blocked: 不適切な内容として断った(課金なし) / crisis: 危機対応の定型文(課金なし)
 */
export type ChatMessageStatus = 'streaming' | 'complete' | 'error' | 'blocked' | 'crisis';

/**
 * knowledge_chunks.source_type と同じ値。出典からどの画面へ飛ぶかを決める。
 * courseだけは例外で、探索役がコースの講義一覧を開いたときの出典(knowledge_chunksには無い)。
 * chat_turnは過去のチャット(スレッド・節・往復のどれを開いても同じ種類で、押すとそのスレッドへ)。
 * webはWebのページ(押すと元のページを新しいタブで開く)。
 */
export type ChatSourceType =
  | 'course'
  | 'chat_turn'
  | 'web'
  | 'review_card'
  | 'deep_note'
  | 'keyword'
  | 'announcement'
  | 'transcript_topic'
  | 'topic_summary'
  | 'fun_fact'
  | 'lecture_summary'
  | 'lecture_moment';

/** 出典の中で引用された区切り(ハイライトする本文)と、その前後1区切り(文脈)。 */
export interface ChatCitationPassage {
  before: string;
  text: string;
  after: string;
}

/** 回答本文の [n] / [Wn] に対応する出典。講義・チャットは数字、Webのページは "W1" のような文字列。 */
export interface ChatCitation {
  n: number | string;
  /** 検索で当たったチャンクのときだけ。探索役が開いた講義・トピック等はnull。 */
  chunk_id: string | null;
  source_type: ChatSourceType;
  source_id: string | null;
  lecture_id: string | null;
  course_id?: string | null;
  /** chat_turnのときだけ。押すとこのスレッドを開く。 */
  thread_id?: string | null;
  /** webのときだけ。元のページ。 */
  url?: string | null;
  /** 例: "CS 161 / Lecture 3 / Deep Note: Heaps" */
  label: string;
  /** 出典のテキスト抜粋(プレビュー表示用) */
  snippet?: string;
  similarity?: number | null;
  /** deep_noteならtopic_number等。画面へのディープリンクに使う。 */
  metadata?: Record<string, unknown>;
  /**
   * 本文で区切りの番号つき([3.5] / [3.5-7])で引用されたときの、その区切り。キーは本文の書き方("5" / "5-7")。
   * 区切りで引用されなかった出典・古い返答・生成中(sourcesイベント)には無い。
   */
  passages?: Record<string, ChatCitationPassage>;
}

export interface ChatThread {
  id: string;
  title: string | null;
  mode: 'learning';
  context_lecture_id: string | null;
  last_message_at: string;
  created_at: string;
}

/**
 * 見ているページ。本文はバックエンドがDBから読んで回答役に渡す(lefture_backend/app/services/chat_screen.py)。
 * deep_note / fun_fact: idがその行。review_card: idが表示中のカード。表紙を見ているときは
 * idが無くtopic_number(講義はlecture_id)。
 */
export interface ChatScreenRef {
  kind: 'deep_note' | 'review_card' | 'fun_fact';
  id?: string;
  topic_number?: number;
}

/** 「Ask」で次の送信に添える選択。before/afterはページの中で選択箇所を特定するためだけに使う。 */
export interface ChatSelection {
  text: string;
  before?: string;
  after?: string;
  /** 選択したページ。今いる画面のページより優先する。 */
  screen?: ChatScreenRef;
}

export interface ChatMessageContext {
  lecture_id?: string;
  selected_text?: string;
  selection_before?: string;
  selection_after?: string;
  screen?: ChatScreenRef;
}

export interface ChatMessage {
  id: string;
  thread_id: string;
  role: ChatMessageRole;
  content: string;
  status: ChatMessageStatus;
  citations: ChatCitation[];
  context: ChatMessageContext;
  credits_charged_micro: number | null;
  created_at: string;
}

/** 生成中に「どの段階か」を画面に出すための状態。 */
export type ChatStage = 'thinking' | 'searching' | 'reasoning' | 'writing';

/** 探索中に何を探しているか(探索役の1周ごと)。 */
export type ChatSearchDetail = 'lectures' | 'chats' | 'web';

/** POST /chat/messages のSSEイベント(バックエンドのrun_chat_turnと1対1)。 */
export type ChatStreamEvent =
  | { type: 'meta'; thread_id: string; user_message_id: string; assistant_message_id: string }
  | {
      type: 'status';
      stage: ChatStage;
      detail?: ChatSearchDetail[];
      query?: string;
      target?: string;
      layer?: string;
      handle?: string;
    }
  | { type: 'sources'; sources: ChatCitation[] }
  | { type: 'delta'; text: string }
  | { type: 'replace'; text: string }
  | { type: 'done'; status: ChatMessageStatus; citations?: ChatCitation[]; credits_charged: number }
  | { type: 'error'; error_code: string; message: string };

/**
 * 送信前の事前チェックで返るerror_code(HTTPステータス付きで返る)。
 * 画面ごとに文言と導線(クレジット購入など)を出し分けるため列挙しておく。
 */
export type ChatRequestErrorCode =
  | 'EMPTY_MESSAGE'
  | 'MESSAGE_TOO_LONG'
  | 'SELECTED_TEXT_TOO_LONG'
  | 'INSUFFICIENT_CREDITS'
  | 'CHAT_RATE_LIMITED'
  | 'CHAT_BLOCKED_COOLDOWN'
  | 'DUPLICATE_MESSAGE'
  | 'THREAD_NOT_FOUND'
  | 'THREAD_BUSY'
  | 'ACCOUNT_SUSPENDED'
  | 'CHAT_FAILED'
  | 'NETWORK';

/** バックエンドの MAX_MESSAGE_CHARS / MAX_SELECTED_TEXT_CHARS と揃える(送信前に画面側でも止める)。 */
export const CHAT_MAX_MESSAGE_CHARS = 4000;
export const CHAT_MAX_SELECTED_TEXT_CHARS = 2000;
