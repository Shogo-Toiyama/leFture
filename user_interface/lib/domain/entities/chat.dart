// lib/domain/entities/chat.dart
//
// 横断チャットボットの型。webappの webapp/src/types/chat.ts と1対1で揃える。
// バックエンド: lefture_backend/app/services/chat_service.py / main.pyの /chat/*
// DB: chat_threads / chat_messages / chat_attachments(本人のみSELECT可。書き込みはバックエンド経由のみ)

/// バックエンドの MAX_MESSAGE_CHARS / MAX_SELECTED_TEXT_CHARS と揃える(送信前に画面側でも止める)。
const chatMaxMessageChars = 4000;
const chatMaxSelectedTextChars = 2000;

/// バックエンドの MAX_ATTACHMENT_CHARS / MAX_ATTACHMENTS_PER_MESSAGE / MAX_ATTACHMENTS_PER_THREAD と揃える。
const chatMaxAttachmentChars = 100000;
const chatMaxAttachmentsPerMessage = 5;
const chatMaxAttachmentsPerThread = 30;
const chatMaxAttachmentTitleChars = 100;

/// 全文で読む資料(選択中)の合計の上限。バックエンドの MAX_SELECTED_TOKENS と揃える。
const chatMaxSelectedTokens = 30000;

/// 全文で読む資料1万トークンあたりの、1ターンの消費の目安(表示専用。webappのCHAT_CREDITS_PER_10K_TOKENSと同じ値)。
/// 請求はバックエンドが実際のトークンで計算する。回答役のモデルを替えたらwebappと一緒に直す。
const chatCreditsPer10kTokens = 0.6;

/// バックエンドの MAX_MENTIONS_PER_MESSAGE と揃える。
const chatMaxMentionsPerMessage = 10;

/// 本文の中の資料の印(バックエンドのchat_attachments.MENTION_RE)。保存する本文もこの形。
final chatMentionPattern = RegExp(r'⟦att:([0-9A-Za-z-]{1,64})⟧');
String chatMentionToken(String id) => '⟦att:$id⟧';

/// バックエンドのchat_files.MAX_UPLOAD_BYTES と揃える(画像・docx・pptxは端末で縮めた後の大きさ)。
const chatMaxFileBytes = <ChatFileKind, int>{
  ChatFileKind.pdf: 100 * 1024 * 1024,
  ChatFileKind.docx: 30 * 1024 * 1024,
  ChatFileKind.pptx: 30 * 1024 * 1024,
  ChatFileKind.image: 30 * 1024 * 1024,
};

// ---------------------------------------------------------------------------
// スレッドとメッセージ
// ---------------------------------------------------------------------------

class ChatThread {
  const ChatThread({
    required this.id,
    this.title,
    this.contextLectureId,
    required this.lastMessageAt,
    required this.createdAt,
  });

  final String id;
  final String? title;
  final String? contextLectureId;
  final DateTime lastMessageAt;
  final DateTime createdAt;

  /// Supabaseから読む列(webappのTHREAD_COLUMNSと同じ)。
  static const columns =
      'id, title, mode, context_lecture_id, last_message_at, created_at';

  factory ChatThread.fromMap(Map<String, dynamic> map) => ChatThread(
    id: map['id'] as String,
    title: map['title'] as String?,
    contextLectureId: map['context_lecture_id'] as String?,
    lastMessageAt: DateTime.parse(map['last_message_at'] as String),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  ChatThread copyWith({String? title, DateTime? lastMessageAt}) => ChatThread(
    id: id,
    title: title ?? this.title,
    contextLectureId: contextLectureId,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    createdAt: createdAt,
  );
}

enum ChatMessageRole { user, assistant }

/// streaming: 生成中 / complete: 完了 / error: 失敗(課金なし)
/// blocked: 不適切な内容として断った(課金なし) / crisis: 危機対応の定型文(課金なし)
/// stopped: 生徒が途中で止めた(止めたところまでの本文。空のこともある。発生した原価の分だけ課金)
enum ChatMessageStatus {
  streaming,
  complete,
  error,
  blocked,
  crisis,
  stopped;

  static ChatMessageStatus parse(Object? raw) => values.firstWhere(
    (s) => s.name == raw,
    orElse: () => ChatMessageStatus.error,
  );

  /// もう変わらない状態か(生成中以外)。
  bool get isFinal => this != streaming;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.status,
    this.citations = const [],
    this.context = const ChatMessageContext(),
    this.creditsChargedMicro,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final ChatMessageRole role;
  final String content;
  final ChatMessageStatus status;
  final List<ChatCitation> citations;
  final ChatMessageContext context;
  final int? creditsChargedMicro;
  final DateTime createdAt;

  /// Supabaseから読む列(webappのMESSAGE_COLUMNSと同じ)。
  static const columns =
      'id, thread_id, role, content, status, citations, context, credits_charged_micro, created_at';

  double get creditsCharged => (creditsChargedMicro ?? 0) / 1000000;

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as String,
    threadId: map['thread_id'] as String,
    role: map['role'] == 'user'
        ? ChatMessageRole.user
        : ChatMessageRole.assistant,
    content: (map['content'] as String?) ?? '',
    status: ChatMessageStatus.parse(map['status']),
    citations: ChatCitation.listFrom(map['citations']),
    context: map['context'] is Map
        ? ChatMessageContext.fromMap(
            Map<String, dynamic>.from(map['context'] as Map),
          )
        : const ChatMessageContext(),
    creditsChargedMicro: (map['credits_charged_micro'] as num?)?.toInt(),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  ChatMessage copyWith({
    String? id,
    String? threadId,
    String? content,
    ChatMessageStatus? status,
    List<ChatCitation>? citations,
    ChatMessageContext? context,
    int? creditsChargedMicro,
  }) => ChatMessage(
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    role: role,
    content: content ?? this.content,
    status: status ?? this.status,
    citations: citations ?? this.citations,
    context: context ?? this.context,
    creditsChargedMicro: creditsChargedMicro ?? this.creditsChargedMicro,
    createdAt: createdAt,
  );
}

// ---------------------------------------------------------------------------
// 出典
// ---------------------------------------------------------------------------

/// 出典の中で引用された区切り(ハイライトする本文)と、その前後1区切り(文脈)。
class ChatCitationPassage {
  const ChatCitationPassage({
    this.before = '',
    required this.text,
    this.after = '',
  });

  final String before;
  final String text;
  final String after;

  factory ChatCitationPassage.fromMap(Map<String, dynamic> map) =>
      ChatCitationPassage(
        before: (map['before'] as String?) ?? '',
        text: (map['text'] as String?) ?? '',
        after: (map['after'] as String?) ?? '',
      );
}

/// 回答本文の [n] / [Wn] に対応する出典。講義・チャットは数字、Webのページは "W1" のような文字列。
///
/// sourceTypeは knowledge_chunks.source_type と同じ値(course / chat_turn / web / chat_attachment /
/// review_card / deep_note / keyword / announcement / transcript_topic / topic_summary / fun_fact /
/// lecture_summary / lecture_moment)。未知の値が来ても壊れないよう文字列のまま持つ。
class ChatCitation {
  const ChatCitation({
    required this.ref,
    this.chunkId,
    required this.sourceType,
    this.sourceId,
    this.lectureId,
    this.courseId,
    this.threadId,
    this.url,
    required this.label,
    this.snippet,
    this.metadata = const {},
    this.passages = const {},
  });

  /// 本文での番号("3" / "W1")。
  final String ref;
  final String? chunkId;
  final String sourceType;
  final String? sourceId;
  final String? lectureId;
  final String? courseId;

  /// chat_turnのときだけ。押すとこのスレッドを開く。
  final String? threadId;

  /// webのときだけ。元のページ。
  final String? url;

  /// 例: "CS 161 / Lecture 3 / Deep Note: Heaps"
  final String label;
  final String? snippet;

  /// deep_noteならtopic_number等。画面へのディープリンクに使う。
  final Map<String, dynamic> metadata;

  /// 本文で区切りの番号つき([3.5] / [3.5-7])で引用されたときの区切り。キーは本文の書き方("5" / "5-7")。
  final Map<String, ChatCitationPassage> passages;

  factory ChatCitation.fromMap(Map<String, dynamic> map) {
    final rawPassages = map['passages'];
    return ChatCitation(
      ref: '${map['n']}',
      chunkId: map['chunk_id'] as String?,
      sourceType: (map['source_type'] as String?) ?? '',
      sourceId: map['source_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      courseId: map['course_id'] as String?,
      threadId: map['thread_id'] as String?,
      url: map['url'] as String?,
      label: (map['label'] as String?) ?? '',
      snippet: map['snippet'] as String?,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      passages: rawPassages is Map
          ? {
              for (final e in rawPassages.entries)
                if (e.value is Map)
                  '${e.key}': ChatCitationPassage.fromMap(
                    Map<String, dynamic>.from(e.value as Map),
                  ),
            }
          : const {},
    );
  }

  static List<ChatCitation> listFrom(Object? raw) => raw is List
      ? [
          for (final e in raw)
            if (e is Map) ChatCitation.fromMap(Map<String, dynamic>.from(e)),
        ]
      : const [];
}

// ---------------------------------------------------------------------------
// 送信に添える文脈
// ---------------------------------------------------------------------------

/// 見ているページ。本文はバックエンドがDBから読んで回答役に渡す(chat_screen.py)。
/// deep_note / fun_fact: idがその行。review_card: idが表示中のカード。表紙を見ているときは
/// idが無くtopicNumber(講義はcontext.lectureId)。
class ChatScreenRef {
  const ChatScreenRef({required this.kind, this.id, this.topicNumber});

  /// 'deep_note' / 'review_card' / 'fun_fact'
  final String kind;
  final String? id;
  final int? topicNumber;

  factory ChatScreenRef.fromMap(Map<String, dynamic> map) => ChatScreenRef(
    kind: map['kind'] as String,
    id: map['id'] as String?,
    topicNumber: (map['topic_number'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (id != null) 'id': id,
    if (topicNumber != null) 'topic_number': topicNumber,
  };
}

/// 「Ask」で次の送信に添える選択。before/afterはページの中で選択箇所を特定するためだけに使う。
class ChatSelection {
  const ChatSelection({
    required this.text,
    this.before,
    this.after,
    this.screen,
    this.replyToMessageId,
  });

  final String text;
  final String? before;
  final String? after;

  /// 選択したページ。今いる画面のページより優先する。
  final ChatScreenRef? screen;

  /// 会話の中のAIの回答の一部を選んだとき、その回答のメッセージID(この場合screenは無い)。
  final String? replyToMessageId;
}

/// 送信で既存の資料を指す(full: 全文で添付して全文で読む枠に入れる / mention: 文中で指すだけ)。
enum ChatAttachmentMode { full, mention }

class ChatAttachmentRef {
  const ChatAttachmentRef({required this.attachmentId, required this.mode});

  final String attachmentId;
  final ChatAttachmentMode mode;
}

/// 全文で読む枠を超えて外した資料・長すぎて全文にできなかった資料(返答の行のcontext、SSEのattachments)。
class ChatAttachmentNotice {
  const ChatAttachmentNotice({
    this.unpinned = const [],
    this.tooLong = const [],
  });

  final List<String> unpinned;
  final List<String> tooLong;

  bool get isEmpty => unpinned.isEmpty && tooLong.isEmpty;

  factory ChatAttachmentNotice.fromMap(Map<String, dynamic> map) =>
      ChatAttachmentNotice(
        unpinned: _stringList(map['unpinned']),
        tooLong: _stringList(map['too_long']),
      );
}

class ChatMessageContext {
  const ChatMessageContext({
    this.lectureId,
    this.selectedText,
    this.selectionBefore,
    this.selectionAfter,
    this.screen,
    this.replyToMessageId,
    this.attachments = const [],
    this.attachmentNotice,
    this.stoppedAttachments = const [],
  });

  final String? lectureId;
  final String? selectedText;
  final String? selectionBefore;
  final String? selectionAfter;
  final ChatScreenRef? screen;

  /// 会話の中のAIの回答の一部を選んで返信したとき、その回答のメッセージID
  final String? replyToMessageId;

  /// userのみ: このメッセージで添付・指した資料と、その渡し方(新しく添付した資料はいつもfull)
  final List<ChatAttachmentRef> attachments;

  /// assistantのみ: このターンで全文読みを外した資料など
  final ChatAttachmentNotice? attachmentNotice;

  /// assistantのみ: 読み込みの途中で止めたため使えなくなった資料
  final List<String> stoppedAttachments;

  factory ChatMessageContext.fromMap(Map<String, dynamic> map) =>
      ChatMessageContext(
        lectureId: map['lecture_id'] as String?,
        selectedText: map['selected_text'] as String?,
        selectionBefore: map['selection_before'] as String?,
        selectionAfter: map['selection_after'] as String?,
        screen: map['screen'] is Map
            ? ChatScreenRef.fromMap(
                Map<String, dynamic>.from(map['screen'] as Map),
              )
            : null,
        replyToMessageId: map['reply_to_message_id'] as String?,
        attachments: map['attachments'] is List
            ? [
                for (final a in map['attachments'] as List)
                  if (a is Map && a['id'] is String)
                    ChatAttachmentRef(
                      attachmentId: a['id'] as String,
                      mode: a['mode'] == 'mention'
                          ? ChatAttachmentMode.mention
                          : ChatAttachmentMode.full,
                    ),
              ]
            : const [],
        attachmentNotice: map['attachment_notice'] is Map
            ? ChatAttachmentNotice.fromMap(
                Map<String, dynamic>.from(map['attachment_notice'] as Map),
              )
            : null,
        stoppedAttachments: _stringList(map['stopped_attachments']),
      );

  /// 送信のリクエストに載せる部分(バックエンドのChatMessageContext)。
  Map<String, dynamic> toRequestJson() => {
    if (lectureId != null) 'lecture_id': lectureId,
    if (selectedText != null) 'selected_text': selectedText,
    if (selectionBefore != null) 'selection_before': selectionBefore,
    if (selectionAfter != null) 'selection_after': selectionAfter,
    if (screen != null) 'screen': screen!.toJson(),
    if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
  };
}

List<String> _stringList(Object? raw) => raw is List
    ? [
        for (final e in raw)
          if (e is String) e,
      ]
    : const [];

// ---------------------------------------------------------------------------
// 生成中の段階とSSEイベント
// ---------------------------------------------------------------------------

/// 生成中に「どの段階か」を画面に出すための状態。readingAttachmentsは添付した資料の確認・目次づくり。
enum ChatStage {
  readingAttachments,
  indexingAttachments,
  thinking,
  searching,
  reasoning,
  writing;

  static ChatStage parse(Object? raw) => switch (raw) {
    'reading_attachments' => readingAttachments,
    'indexing_attachments' => indexingAttachments,
    'searching' => searching,
    'reasoning' => reasoning,
    'writing' => writing,
    _ => thinking,
  };
}

/// POST /chat/messages のSSEイベント(バックエンドのrun_chat_turnと1対1)。
sealed class ChatStreamEvent {
  const ChatStreamEvent();

  /// "event: xxx" の名前と、data のJSONから作る。知らないイベントはnull(読み飛ばす)。
  static ChatStreamEvent? fromSse(String name, Map<String, dynamic> data) =>
      switch (name) {
        'meta' => ChatMetaEvent(
          threadId: data['thread_id'] as String,
          userMessageId: data['user_message_id'] as String,
          assistantMessageId: data['assistant_message_id'] as String,
        ),
        'status' => ChatStatusEvent(
          stage: ChatStage.parse(data['stage']),
          detail: _stringList(data['detail']),
          query: data['query'] as String?,
          target: data['target'] as String?,
          layer: data['layer'] as String?,
          handle: data['handle'] as String?,
        ),
        'sources' => ChatSourcesEvent(ChatCitation.listFrom(data['sources'])),
        'attachments' => ChatAttachmentsEvent(
          ChatAttachmentNotice.fromMap(data),
        ),
        'thought' => ChatThoughtEvent((data['text'] as String?) ?? ''),
        'delta' => ChatDeltaEvent((data['text'] as String?) ?? ''),
        'replace' => ChatReplaceEvent((data['text'] as String?) ?? ''),
        'done' => ChatDoneEvent(
          status: ChatMessageStatus.parse(data['status']),
          citations: data.containsKey('citations')
              ? ChatCitation.listFrom(data['citations'])
              : null,
          creditsCharged: (data['credits_charged'] as num?)?.toDouble() ?? 0,
        ),
        'error' => ChatErrorEvent(
          errorCode: (data['error_code'] as String?) ?? 'CHAT_FAILED',
          message: (data['message'] as String?) ?? '',
        ),
        _ => null,
      };
}

/// 最初に届く。新しい会話ならここでスレッドidが決まる。
class ChatMetaEvent extends ChatStreamEvent {
  const ChatMetaEvent({
    required this.threadId,
    required this.userMessageId,
    required this.assistantMessageId,
  });

  final String threadId;
  final String userMessageId;
  final String assistantMessageId;
}

class ChatStatusEvent extends ChatStreamEvent {
  const ChatStatusEvent({
    required this.stage,
    this.detail = const [],
    this.query,
    this.target,
    this.layer,
    this.handle,
  });

  final ChatStage stage;

  /// 探索中に何を探しているか('lectures' / 'chats' / 'web' / 'attachments')
  final List<String> detail;
  final String? query;
  final String? target;
  final String? layer;
  final String? handle;
}

class ChatSourcesEvent extends ChatStreamEvent {
  const ChatSourcesEvent(this.sources);
  final List<ChatCitation> sources;
}

class ChatAttachmentsEvent extends ChatStreamEvent {
  const ChatAttachmentsEvent(this.notice);
  final ChatAttachmentNotice notice;
}

class ChatThoughtEvent extends ChatStreamEvent {
  const ChatThoughtEvent(this.text);
  final String text;
}

class ChatDeltaEvent extends ChatStreamEvent {
  const ChatDeltaEvent(this.text);
  final String text;
}

/// 本文をまるごと差し替える(安全フィルタで書き直したときなど)。
class ChatReplaceEvent extends ChatStreamEvent {
  const ChatReplaceEvent(this.text);
  final String text;
}

class ChatDoneEvent extends ChatStreamEvent {
  const ChatDoneEvent({
    required this.status,
    this.citations,
    required this.creditsCharged,
  });

  final ChatMessageStatus status;
  final List<ChatCitation>? citations;
  final double creditsCharged;
}

class ChatErrorEvent extends ChatStreamEvent {
  const ChatErrorEvent({required this.errorCode, required this.message});

  final String errorCode;
  final String message;
}

/// 送信前の事前チェックで弾かれた(ストリームが始まる前にHTTPエラーが返った)場合や、
/// 通信が切れた場合に投げる。codeで画面の出し分けをする(webappのChatRequestErrorCodeと同じ値。
/// 例: INSUFFICIENT_CREDITS / CHAT_RATE_LIMITED / THREAD_BUSY / NETWORK)。
class ChatRequestException implements Exception {
  const ChatRequestException(
    this.code,
    this.message, {
    this.status,
    this.detail = const {},
  });

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> detail;

  @override
  String toString() => 'ChatRequestException($code, $status): $message';
}

// ---------------------------------------------------------------------------
// 添付資料(バックエンド: chat_attachments.py / chat_files.py、DB: chat_attachments)
// ---------------------------------------------------------------------------

/// draft: ファイルをアップロードして、まだ送っていない / processing: 確認・目次づくりの途中 /
/// ready: 使える / blocked: 断った / failed: 処理に失敗した
enum ChatAttachmentStatus {
  draft,
  processing,
  ready,
  blocked,
  failed;

  static ChatAttachmentStatus parse(Object? raw) => values.firstWhere(
    (s) => s.name == raw,
    orElse: () => ChatAttachmentStatus.failed,
  );
}

/// ファイルの種類(バックエンドのchat_files.KIND_BY_EXTENSION)。
enum ChatFileKind {
  pdf,
  docx,
  pptx,
  image;

  static ChatFileKind? tryParse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// 目次の1節。start/endは本文(content)の文字位置。
class ChatAttachmentSection {
  const ChatAttachmentSection({
    required this.index,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  final int index;
  final String title;
  final String description;
  final int start;
  final int end;

  factory ChatAttachmentSection.fromMap(Map<String, dynamic> map) =>
      ChatAttachmentSection(
        index: (map['index'] as num?)?.toInt() ?? 0,
        title: (map['title'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        start: (map['start'] as num?)?.toInt() ?? 0,
        end: (map['end'] as num?)?.toInt() ?? 0,
      );
}

/// 送った資料(DBの行)。
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.threadId,
    this.messageId,
    required this.kind,
    required this.status,
    this.title,
    required this.content,
    required this.charCount,
    required this.tokenCount,
    required this.selected,
    this.summary,
    this.sections = const [],
    required this.createdAt,
    this.fileName,
    this.pageCount,
    this.metadata = const {},
  });

  final String id;
  final String threadId;

  /// 添付したuserメッセージ
  final String? messageId;

  /// 'text'(貼り付け・テキストファイル)か、ChatFileKindの名前
  final String kind;
  final ChatAttachmentStatus status;
  final String? title;
  final String content;
  final int charCount;

  /// 全文を渡したときのトークン数の概算(バックエンドのestimate_tokens)。
  final int tokenCount;

  /// 全文で読む資料か。
  final bool selected;
  final String? summary;
  final List<ChatAttachmentSection> sections;
  final DateTime createdAt;

  /// ファイルのとき: 元の名前・PDFのページ数 / pptxのスライド数
  final String? fileName;
  final int? pageCount;

  /// 追加のメタデータ(圧縮フラグ等)
  final Map<String, dynamic> metadata;

  bool get isCompressed => metadata['compressed'] == true;

  ChatFileKind? get fileKind => ChatFileKind.tryParse(kind);

  /// Supabaseから読む列(webappのATTACHMENT_COLUMNSと同じ)。
  static const columns =
      'id, thread_id, message_id, kind, status, title, content, char_count, token_count, selected, summary, sections, created_at, file_name, page_count, metadata';

  factory ChatAttachment.fromMap(Map<String, dynamic> map) => ChatAttachment(
    id: map['id'] as String,
    threadId: map['thread_id'] as String,
    messageId: map['message_id'] as String?,
    kind: (map['kind'] as String?) ?? 'text',
    status: ChatAttachmentStatus.parse(map['status']),
    title: map['title'] as String?,
    content: (map['content'] as String?) ?? '',
    charCount: (map['char_count'] as num?)?.toInt() ?? 0,
    tokenCount: (map['token_count'] as num?)?.toInt() ?? 0,
    selected: map['selected'] == true,
    summary: map['summary'] as String?,
    sections: map['sections'] is List
        ? [
            for (final s in map['sections'] as List)
              if (s is Map)
                ChatAttachmentSection.fromMap(Map<String, dynamic>.from(s)),
          ]
        : const [],
    createdAt: DateTime.parse(map['created_at'] as String),
    fileName: map['file_name'] as String?,
    pageCount: (map['page_count'] as num?)?.toInt(),
    metadata: map['metadata'] is Map
        ? Map<String, dynamic>.from(map['metadata'] as Map)
        : const {},
  );
}

/// 送信と一緒に新しく添付する資料(テキストの下書き、またはアップロードして取り出したファイル)。
/// 新しく添付する資料は、いつも全文で添付する。
sealed class ChatNewAttachment {
  const ChatNewAttachment();
}

/// 送るまで何度でも直せるテキストの資料。localIdは本文の印 ⟦att:localId⟧ の仮のidにもなる
/// (サーバーが本物のidに直す)。
class ChatTextAttachment extends ChatNewAttachment {
  const ChatTextAttachment({
    required this.localId,
    required this.title,
    required this.content,
  });

  final String localId;
  final String title;
  final String content;
}

/// 送る前にアップロードして取り出したファイル(draftの行)。
class ChatFileAttachment extends ChatNewAttachment {
  const ChatFileAttachment({
    required this.attachmentId,
    this.title = '',
    this.fileName = '',
    this.fileKind,
  });

  final String attachmentId;
  final String title;

  /// 送れなかったとき入力欄に資料のチップを戻すための、元の名前と種類。
  final String fileName;
  final ChatFileKind? fileKind;
}

/// ファイルのアップロード先(POST /chat/attachments/uploads の返事)。
class ChatUploadTarget {
  const ChatUploadTarget({
    required this.attachmentId,
    required this.uploadUrl,
    required this.contentType,
    required this.kind,
    required this.maxBytes,
  });

  final String attachmentId;
  final String uploadUrl;
  final String contentType;
  final ChatFileKind kind;
  final int maxBytes;

  factory ChatUploadTarget.fromMap(Map<String, dynamic> map) =>
      ChatUploadTarget(
        attachmentId: map['attachment_id'] as String,
        uploadUrl: map['upload_url'] as String,
        contentType: map['content_type'] as String,
        kind: ChatFileKind.tryParse(map['kind']) ?? ChatFileKind.pdf,
        maxBytes: (map['max_bytes'] as num?)?.toInt() ?? 0,
      );
}

/// 送る前に取り出して分かったこと(バックエンドのchat_files.draft_info)。
class ChatFileInfo {
  const ChatFileInfo({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.fileSize,
    this.pageCount,
    required this.textChars,
    required this.estimatedChars,
    required this.visionCount,
    this.visionPages = const [],
    required this.estimatedTokens,
  });

  final String id;
  final ChatFileKind kind;
  final String fileName;
  final int fileSize;
  final int? pageCount;
  final int textChars;
  final int estimatedChars;

  /// 画像として読む(ビジョンで書き起こす)ページ・画像の数
  final int visionCount;
  final List<String> visionPages;
  final int estimatedTokens;

  factory ChatFileInfo.fromMap(Map<String, dynamic> map) => ChatFileInfo(
    id: map['id'] as String,
    kind: ChatFileKind.tryParse(map['kind']) ?? ChatFileKind.pdf,
    fileName: (map['file_name'] as String?) ?? '',
    fileSize: (map['file_size'] as num?)?.toInt() ?? 0,
    pageCount: (map['page_count'] as num?)?.toInt(),
    textChars: (map['text_chars'] as num?)?.toInt() ?? 0,
    estimatedChars: (map['estimated_chars'] as num?)?.toInt() ?? 0,
    visionCount: (map['vision_count'] as num?)?.toInt() ?? 0,
    visionPages: _stringList(map['vision_pages']),
    estimatedTokens: (map['estimated_tokens'] as num?)?.toInt() ?? 0,
  );
}

/// 添付したファイルを開くための短い署名付きURL(GET /chat/attachments/{id}/file の返事)。
class ChatFileLink {
  const ChatFileLink({
    required this.url,
    required this.fileName,
    required this.kind,
    required this.contentType,
  });

  final String url;
  final String fileName;
  final String kind;
  final String contentType;

  factory ChatFileLink.fromMap(Map<String, dynamic> map) => ChatFileLink(
    url: map['url'] as String,
    fileName: (map['file_name'] as String?) ?? '',
    kind: (map['kind'] as String?) ?? '',
    contentType: (map['content_type'] as String?) ?? '',
  );
}

class ChatThreadNoteItem {
  const ChatThreadNoteItem({
    required this.text,
    this.sourceTurn,
    this.needsSource = false,
  });

  final String text;
  final int? sourceTurn;
  final bool needsSource;

  factory ChatThreadNoteItem.fromMap(Map<String, dynamic> map) => ChatThreadNoteItem(
    text: (map['text'] as String?) ?? '',
    sourceTurn: (map['source_turn'] as num?)?.toInt(),
    needsSource: (map['needs_source'] as bool?) ?? false,
  );
}

class ChatThreadNotes {
  const ChatThreadNotes({
    this.stylePreferences = const [],
    this.context = const [],
    this.purpose = const [],
    this.unresolved = const [],
  });

  final List<ChatThreadNoteItem> stylePreferences;
  final List<ChatThreadNoteItem> context;
  final List<ChatThreadNoteItem> purpose;
  final List<ChatThreadNoteItem> unresolved;

  bool get isEmpty =>
      stylePreferences.isEmpty &&
      context.isEmpty &&
      purpose.isEmpty &&
      unresolved.isEmpty;

  factory ChatThreadNotes.fromMap(Map<String, dynamic> map) {
    List<ChatThreadNoteItem> parseList(dynamic list) {
      if (list is! List) return const [];
      return list
          .map((item) => ChatThreadNoteItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    return ChatThreadNotes(
      stylePreferences: parseList(map['style_preferences']),
      context: parseList(map['context']),
      purpose: parseList(map['purpose']),
      unresolved: parseList(map['unresolved']),
    );
  }
}

