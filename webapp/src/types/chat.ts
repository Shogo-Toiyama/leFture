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
 * chat_attachmentはこの会話に添付した資料の目次・節(押すと引用箇所のプレビューだけ)。
 */
export type ChatSourceType =
  | 'course'
  | 'chat_turn'
  | 'web'
  | 'chat_attachment'
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

/** 送信で既存の資料を指す(full: 全文で添付して全文で読む枠に入れる / mention: 文中で指すだけ)。 */
export interface ChatAttachmentRef {
  attachment_id: string;
  mode: 'full' | 'mention';
}

/** 全文で読む枠を超えて外した資料・長すぎて全文にできなかった資料(返答の行のcontext、SSEのattachments)。 */
export interface ChatAttachmentNotice {
  unpinned: string[];
  too_long: string[];
}

export interface ChatMessageContext {
  lecture_id?: string;
  selected_text?: string;
  selection_before?: string;
  selection_after?: string;
  screen?: ChatScreenRef;
  /** userのみ: このメッセージで添付・指した資料と、その渡し方(新しく添付した資料はいつもfull) */
  attachments?: Array<{ id: string; mode: 'full' | 'mention' }>;
  /** assistantのみ: このターンで全文読みを外した資料など */
  attachment_notice?: ChatAttachmentNotice;
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

/** 生成中に「どの段階か」を画面に出すための状態。reading_attachmentsは添付した資料の確認・目次づくり。 */
export type ChatStage = 'reading_attachments' | 'thinking' | 'searching' | 'reasoning' | 'writing';

/** 探索中に何を探しているか(探索役の1周ごと)。attachmentsは添付資料の目次・節を開いている。 */
export type ChatSearchDetail = 'lectures' | 'chats' | 'web' | 'attachments';

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
  | ({ type: 'attachments' } & ChatAttachmentNotice)
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
  | 'EMPTY_ATTACHMENT'
  | 'ATTACHMENT_TOO_LONG'
  | 'TOO_MANY_ATTACHMENTS'
  | 'THREAD_ATTACHMENT_LIMIT'
  | 'ATTACHMENT_NOT_FOUND'
  | 'TOO_MANY_MENTIONS'
  | 'ATTACHMENT_NOT_READY'
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

// ---------------------------------------------------------------------------
// 添付資料(バックエンド: lefture_backend/app/services/chat_attachments.py、DB: chat_attachments)
// 資料はスレッドごと。送信と一緒に届き、そのターンの最初に審査・要約・目次づくりをする。
// 送った後は中身を変えられない(外すことはできる)。
// ---------------------------------------------------------------------------

/** バックエンドの MAX_ATTACHMENT_CHARS / MAX_ATTACHMENTS_PER_MESSAGE / MAX_ATTACHMENTS_PER_THREAD と揃える。 */
export const CHAT_MAX_ATTACHMENT_CHARS = 100_000;
export const CHAT_MAX_ATTACHMENTS_PER_MESSAGE = 5;
export const CHAT_MAX_ATTACHMENTS_PER_THREAD = 30;
export const CHAT_MAX_ATTACHMENT_TITLE_CHARS = 100;

/**
 * 全文で読む資料(選択中)の合計の上限。バックエンドの MAX_SELECTED_TOKENS と揃える
 * (超える選択はバックエンドも断るが、画面でも先に止めて理由を出す)。
 */
export const CHAT_MAX_SELECTED_TOKENS = 30_000;
/**
 * 全文で読む資料1万トークンあたりの、1ターンの消費の目安(回答役の入力原価 × チャットの請求倍率)。
 * 一覧の「1回あたり約+Nクレジット」の表示にだけ使う目安で、請求はバックエンドが実際のトークンで計算する。
 * 回答役 GPT-6 Luna の入力$0.10/100万トークン × CHAT_CREDIT_MARKUP 1.5 × 300クレジット/$ = 0.45
 * (推論ターンも同じLunaなので同じ)。回答役のモデルを替えたらここも直す
 * (2026-10-05まで2.5 Flash $0.30 の1.35のままで、表示が約3倍になっていた)。
 */
export const CHAT_CREDITS_PER_10K_TOKENS = 0.45;

/**
 * draft: ファイルをアップロードして、まだ送っていない(一覧には出ない) / processing: 確認・目次づくりの途中 /
 * ready: 使える / blocked: 断った / failed: 処理に失敗した
 */
export type ChatAttachmentStatus = 'draft' | 'processing' | 'ready' | 'blocked' | 'failed';

/** ファイルの種類(バックエンドのchat_files.KIND_BY_EXTENSION)。textは貼り付け・テキストファイル。 */
export type ChatFileKind = 'pdf' | 'docx' | 'pptx' | 'image';
export type ChatAttachmentKind = 'text' | ChatFileKind;

/** 目次の1節。start/endは本文(content)の文字位置。 */
export interface ChatAttachmentSection {
  index: number;
  title: string;
  description: string;
  start: number;
  end: number;
}

/** 送った資料(DBの行)。 */
export interface ChatAttachment {
  id: string;
  thread_id: string;
  /** 添付したuserメッセージ */
  message_id: string | null;
  kind: ChatAttachmentKind;
  status: ChatAttachmentStatus;
  title: string | null;
  content: string;
  char_count: number;
  /** 全文を渡したときのトークン数の概算(バックエンドのestimate_tokens)。 */
  token_count: number;
  /** 全文で読む資料か(本人が選ぶ。新しい資料は上限に収まれば自動で選ばれる)。 */
  selected: boolean;
  summary: string | null;
  sections: ChatAttachmentSection[];
  created_at: string;
  /** ファイルのとき: 元の名前・PDFのページ数 / pptxのスライド数 */
  file_name: string | null;
  page_count: number | null;
}

/**
 * 本文の中の資料の印(バックエンドのchat_attachments.MENTION_RE)。保存する本文もこの形。
 * 送るときの新しいテキストの資料はまだidが無いので、下書きのlocalIdを入れて送る(サーバーが本物のidに直す)。
 */
export const CHAT_MENTION_RE = /⟦att:([0-9A-Za-z-]{1,64})⟧/g;
export const chatMentionToken = (id: string) => `⟦att:${id}⟧`;
/** バックエンドの MAX_MENTIONS_PER_MESSAGE と揃える。 */
export const CHAT_MAX_MENTIONS_PER_MESSAGE = 10;

/** 送る前の資料(入力欄の下書き)。テキストは送るまで何度でも直せる。localIdは本文の印の仮のidにもなる。 */
export interface ChatTextDraft {
  localId: string;
  kind: 'text';
  title: string;
  content: string;
}

/**
 * ファイルの下書き。選ぶ → 端末で縮める → アップロード → バックエンドが中身を取り出す(LLMなし)
 * → ready。readyになるまで送れない。
 */
export interface ChatFileDraft {
  localId: string;
  kind: 'file';
  fileKind: ChatFileKind;
  fileName: string;
  /** 本人が付けた名前(今は使わない。空ならAIが付ける) */
  title: string;
  stage: 'compressing' | 'uploading' | 'reading' | 'ready' | 'error';
  /** uploadingのときの進み具合(0〜1) */
  progress?: number;
  /** アップロード先を頼んだ後(draftの行のid) */
  attachmentId?: string;
  info?: ChatFileInfo;
  errorCode?: string;
  errorDetail?: Record<string, unknown>;
  /** 画像のとき: チップに出す小さな見本(object URL) */
  previewUrl?: string;
  /** PDFのとき: 送る前に中身を確かめるための端末のファイル(object URL) */
  localUrl?: string;
}

export type ChatDraftAttachment = ChatTextDraft | ChatFileDraft;

/** 送る前に取り出して分かったこと(バックエンドのchat_files.draft_info)。 */
export interface ChatFileInfo {
  id: string;
  kind: ChatFileKind;
  file_name: string;
  file_size: number;
  page_count: number | null;
  text_chars: number;
  estimated_chars: number;
  /** 画像として読む(ビジョンで書き起こす)ページ・画像の数 */
  vision_count: number;
  vision_pages: string[];
  estimated_tokens: number;
}

/** バックエンドのchat_files.MAX_UPLOAD_BYTES と揃える(画像・docx・pptxは端末で縮めた後の大きさ)。 */
export const CHAT_MAX_FILE_BYTES: Record<ChatFileKind, number> = {
  pdf: 100 * 1024 * 1024,
  docx: 30 * 1024 * 1024,
  pptx: 30 * 1024 * 1024,
  image: 30 * 1024 * 1024,
};
