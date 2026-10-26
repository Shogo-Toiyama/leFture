// lib/application/chat/chat_conversation.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/auth/authed_http.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_conversation.g.dart';

/// 画面表示用のメッセージ。サーバーの行に、送信中・失敗などの画面専用の状態を足したもの
/// (webappのLocalChatMessageと同じ)。
class LocalChatMessage {
  const LocalChatMessage({
    required this.message,
    this.failedCode,
    this.failedDetail = const {},
    this.stage,
    this.thoughtText,
    this.searchDetail = const [],
    this.searchQuery,
    this.searchTarget,
    this.searchLayer,
    this.searchHandle,
    this.pendingSources,
    this.reconnecting = false,
    this.localAttachments = const [],
    this.localReferences = const [],
    this.stopping = false,
    this.stopFailed = false,
  });

  final ChatMessage message;

  /// 送信前チェックで弾かれたuserメッセージ(サーバーには保存されていない)。error_codeが入る。
  final String? failedCode;
  final Map<String, dynamic> failedDetail;

  /// 生成中の段階(assistantのみ)。
  final ChatStage? stage;

  /// 生成中の思考テキスト(assistantのみ。完了後は破棄される)。
  final String? thoughtText;

  /// stageがsearchingのとき、今の周で探しているもの('lectures' / 'chats' / 'web' / 'attachments')。
  final List<String> searchDetail;
  final String? searchQuery;
  final String? searchTarget;
  final String? searchLayer;
  final String? searchHandle;

  /// 生成中に届いた出典候補(assistantのみ。完了後は本文で使われたcitationsだけが残る)。
  final List<ChatCitation>? pendingSources;

  /// 受信中に通信が切れ、サーバー側で生成が終わるのを待っている。
  final bool reconnecting;

  /// この送信で添付した資料の下書き(userのみ)。サーバーの資料一覧が読み直されるまでの表示と、
  /// 送れなかったときの再送に使う。
  final List<ChatNewAttachment> localAttachments;

  /// この送信で指した既存の資料(userのみ。送れなかったときの再送に使う)。
  final List<ChatAttachmentRef> localReferences;

  /// 停止を押して、サーバーが止めたところまでで確定するのを待っている(assistantのみ)。
  final bool stopping;

  /// 停止のリクエストが届かなかった(受信は続いている。もう一度押せる)。
  final bool stopFailed;

  String get id => message.id;
  bool get isUser => message.role == ChatMessageRole.user;
  bool get isStreaming => message.status == ChatMessageStatus.streaming;

  LocalChatMessage copyWith({
    ChatMessage? message,
    ({String code, Map<String, dynamic> detail})? failed,
    ChatStage? stage,
    String? thoughtText,
    List<String>? searchDetail,
    String? searchQuery,
    String? searchTarget,
    String? searchLayer,
    String? searchHandle,
    List<ChatCitation>? pendingSources,
    bool? reconnecting,
    bool? stopping,
    bool? stopFailed,
    bool clearProgress = false,
  }) {
    return LocalChatMessage(
      message: message ?? this.message,
      failedCode: failed?.code ?? failedCode,
      failedDetail: failed?.detail ?? failedDetail,
      stage: clearProgress ? null : stage ?? this.stage,
      thoughtText: clearProgress ? null : thoughtText ?? this.thoughtText,
      searchDetail: clearProgress
          ? const []
          : searchDetail ?? this.searchDetail,
      searchQuery: clearProgress ? null : searchQuery ?? this.searchQuery,
      searchTarget: clearProgress ? null : searchTarget ?? this.searchTarget,
      searchLayer: clearProgress ? null : searchLayer ?? this.searchLayer,
      searchHandle: clearProgress ? null : searchHandle ?? this.searchHandle,
      pendingSources: clearProgress
          ? null
          : pendingSources ?? this.pendingSources,
      reconnecting: reconnecting ?? this.reconnecting,
      localAttachments: localAttachments,
      localReferences: localReferences,
      stopping: stopping ?? this.stopping,
      stopFailed: stopFailed ?? this.stopFailed,
    );
  }
}

/// 1つの会話の表示状態(webappのuseChatConversationが返すもの)。
class ChatConversationState {
  const ChatConversationState({
    this.threadId,
    this.messages = const [],
    this.attachments = const [],
    this.loading = false,
    this.loadFailed = false,
    this.sending = false,
    this.stopping = false,
    this.hasMore = false,
    this.loadingOlder = false,
  });

  /// nullなら新しい会話(最初の送信でサーバーがスレッドを作る)。
  final String? threadId;
  final List<LocalChatMessage> messages;

  /// このスレッドの資料(外したものを除く、添付順)。
  final List<ChatAttachment> attachments;
  final bool loading;

  /// 読み込みに失敗し、見せられるキャッシュも無い。
  final bool loadFailed;
  final bool sending;

  /// 停止を押してから、止まった行が返るまで。
  final bool stopping;

  /// まだ読み込める過去のメッセージがあるか。
  final bool hasMore;

  /// 過去のメッセージを読み込み中か。
  final bool loadingOlder;

  ChatConversationState copyWith({
    String? Function()? threadId,
    List<LocalChatMessage>? messages,
    List<ChatAttachment>? attachments,
    bool? loading,
    bool? loadFailed,
    bool? sending,
    bool? stopping,
    bool? hasMore,
    bool? loadingOlder,
  }) => ChatConversationState(
    threadId: threadId != null ? threadId() : this.threadId,
    messages: messages ?? this.messages,
    attachments: attachments ?? this.attachments,
    loading: loading ?? this.loading,
    loadFailed: loadFailed ?? this.loadFailed,
    sending: sending ?? this.sending,
    stopping: stopping ?? this.stopping,
    hasMore: hasMore ?? this.hasMore,
    loadingOlder: loadingOlder ?? this.loadingOlder,
  );
}

/// 通信切断後に、サーバー側での生成完了をDBで待つ間隔と回数(約2分)。テストでは短くする。
@visibleForTesting
Duration chatReconnectPollInterval = const Duration(seconds: 3);
@visibleForTesting
int chatReconnectPollMaxAttempts = 40;

/// 今開いている会話の表示と送信(webappのuseChatConversationと同じ役割)。
///
/// シートは1つしか開かないので、アプリで1つだけ持つ。シートを閉じても受信は続けるので、
/// 開き直せば生成途中の返答がそのまま見える。裏に回って接続が切れたときは、返答の生成・保存・課金は
/// サーバー側で最後まで走り切るので、戻ってきたとき([onAppResumed])にDBから読み直す。
@Riverpod(keepAlive: true)
class ChatConversation extends _$ChatConversation {
  static const _pageSize = 20;

  /// 今受信している返答。返答のIDはmetaイベントで届くので、それより前に停止を押したら
  /// stopRequestedを立てておき、metaが届いた瞬間に止める。
  _ActiveStream? _stream;

  /// 読み込みの世代。別の会話に切り替えたとき、古い読み込みの結果を捨てるために使う。
  int _generation = 0;

  /// 裏で走らせているキャッシュへの保存。画面は待たないが、[settle]で完了を待てる。
  final Set<Future<void>> _background = {};

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatCacheDrift get _cache => ref.read(chatCacheDriftProvider);
  String? get _uid => _repo.currentUserId;

  @override
  ChatConversationState build() => const ChatConversationState();

  // -------------------------------------------------------------------------
  // 開く
  // -------------------------------------------------------------------------

  /// スレッドを開く(nullなら新しい会話)。前の会話の受信は止める(サーバー側の生成は続き、
  /// その会話を開き直せばDBから読める。止めないと送信中の状態が残り、切り替え先で入力欄が
  /// 使えないままになる)。
  Future<void> openThread(String? threadId) async {
    if (threadId != null &&
        threadId == state.threadId &&
        state.messages.isNotEmpty) {
      // 今開いている会話。読み直さない(生成中の表示を消さないため)。
      return;
    }
    await _detachStream();
    final generation = ++_generation;
    if (threadId == null) {
      state = const ChatConversationState();
      return;
    }

    // 前回の内容を先に出す(あれば)。資料は前の会話のものを一瞬でも見せない。
    final uid = _uid;
    final cached = uid == null
        ? <ChatMessage>[]
        : await _cache.getMessages(uid, threadId, limit: _pageSize);
    if (generation != _generation) return;
    state = ChatConversationState(
      threadId: threadId,
      messages: [for (final m in cached) LocalChatMessage(message: m)],
      loading: true,
      hasMore: false,
    );
    unawaited(_refreshAttachments(threadId));
    await _load(threadId, generation, hadCache: cached.isNotEmpty);
  }

  /// 今の会話をサーバーの内容で読み直す(読み込みに失敗したときの「再読み込み」など)。
  Future<void> reload() async {
    final threadId = state.threadId;
    if (threadId == null) return;
    state = state.copyWith(loading: true, loadFailed: false);
    await _load(threadId, ++_generation, hadCache: state.messages.isNotEmpty);
  }

  Future<void> _load(
    String threadId,
    int generation, {
    required bool hadCache,
  }) async {
    try {
      final rows = await _repo.fetchMessageRows(
        threadId,
        limit: _pageSize + 1,
      );
      if (generation != _generation) return;
      final hasMore = rows.length > _pageSize;
      final keptRows = hasMore ? rows.sublist(rows.length - _pageSize) : rows;
      final messages = [for (final r in keptRows) ChatMessage.fromMap(r)];
      state = state.copyWith(
        messages: [for (final m in messages) LocalChatMessage(message: m)],
        loading: false,
        loadFailed: false,
        hasMore: hasMore,
      );
      final uid = _uid;
      if (uid != null) {
        _inBackground(_cache.replaceMessages(uid, threadId, keptRows));
      }
      // 生成中にアプリを閉じた等: まだstreamingの返答は完了を待つ
      for (final m in messages) {
        if (m.role == ChatMessageRole.assistant &&
            m.status == ChatMessageStatus.streaming) {
          unawaited(_waitForServerCompletion(m.id, generation));
        }
      }
    } catch (_) {
      if (generation != _generation) return;
      // キャッシュを出せているなら、そのまま見せる(オフラインでも前回の内容は読める)
      state = state.copyWith(loading: false, loadFailed: !hadCache);
    }
  }

  /// 過去のメッセージを読み込む(上へスクロールしたとき)。
  Future<void> loadOlderMessages() async {
    final threadId = state.threadId;
    if (threadId == null ||
        !state.hasMore ||
        state.loadingOlder ||
        state.loading ||
        state.messages.isEmpty) {
      return;
    }
    final oldest = state.messages.first;
    final beforeCreatedAt = oldest.message.createdAt.toUtc().toIso8601String();
    state = state.copyWith(loadingOlder: true);
    final generation = _generation;

    try {
      final rows = await _repo.fetchMessageRows(
        threadId,
        limit: _pageSize + 1,
        beforeCreatedAt: beforeCreatedAt,
      );
      if (generation != _generation) return;
      final hasMore = rows.length > _pageSize;
      final keptRows = hasMore ? rows.sublist(rows.length - _pageSize) : rows;
      final olderMessages = [for (final r in keptRows) ChatMessage.fromMap(r)];

      final existingIds = {for (final m in state.messages) m.id};
      final uniqueOlder = [
        for (final m in olderMessages)
          if (!existingIds.contains(m.id)) LocalChatMessage(message: m),
      ];

      state = state.copyWith(
        messages: [...uniqueOlder, ...state.messages],
        loadingOlder: false,
        hasMore: hasMore,
      );

      final uid = _uid;
      if (uid != null && keptRows.isNotEmpty) {
        _inBackground(_cache.saveMessages(uid, threadId, keptRows));
      }
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(loadingOlder: false);
    }
  }

  Future<void> _refreshAttachments(String? threadId) async {
    if (threadId == null) {
      state = state.copyWith(attachments: const []);
      return;
    }
    try {
      final rows = await _repo.listAttachments(threadId);
      if (state.threadId == threadId) state = state.copyWith(attachments: rows);
    } catch (_) {
      // 読めなくても会話は使える。次の往復の後にもう一度読む
    }
  }

  // -------------------------------------------------------------------------
  // 送信
  // -------------------------------------------------------------------------

  /// メッセージを送り、返答をSSEで受け取って表示に反映する。送る前に弾かれたとき(残高不足など)は
  /// [onRejected]が呼ばれる。編集・作り直しのときは弾かれても会話は元のまま(サーバーでは何も消えていない)。
  Future<void> send(
    String rawContent, {
    ChatMessageContext context = const ChatMessageContext(),
    List<ChatNewAttachment> newAttachments = const [],
    List<ChatAttachmentRef> references = const [],
    String? replaceFromMessageId,
    void Function(String code, Map<String, dynamic> detail)? onRejected,
  }) async {
    final content = rawContent.trim();
    // 資料だけを送るのは許す
    if ((content.isEmpty && newAttachments.isEmpty && references.isEmpty) ||
        state.sending) {
      return;
    }

    // 画面のチップ用に、添付・指した資料と渡し方を残す(サーバーも同じものを保存する)
    final sentContext = ChatMessageContext(
      lectureId: context.lectureId,
      selectedText: context.selectedText,
      selectionBefore: context.selectionBefore,
      selectionAfter: context.selectionAfter,
      screen: context.screen,
      replyToMessageId: context.replyToMessageId,
      attachments: [
        ...references,
        for (final a in newAttachments)
          ChatAttachmentRef(
            attachmentId: switch (a) {
              ChatTextAttachment() => a.localId,
              ChatFileAttachment() => a.attachmentId,
            },
            mode: ChatAttachmentMode.full,
          ),
      ],
    );

    final request = ChatSendRequest(
      threadId: state.threadId,
      content: content,
      context: context,
      newAttachments: newAttachments,
      references: references,
      replaceFromMessageId: replaceFromMessageId,
    );
    final clientMessageId = request.clientMessageId;
    final now = DateTime.now().toUtc();
    var userId = 'local-user-$clientMessageId';
    var assistantId = 'local-assistant-$clientMessageId';
    var receivedMeta = false;
    final baseThreadId = state.threadId ?? '';

    // 編集・作り直し: そのメッセージから後ろを画面から外す(送る前に弾かれたら戻す)
    final cut = replaceFromMessageId == null
        ? -1
        : state.messages.indexWhere((m) => m.id == replaceFromMessageId);
    final removed = cut >= 0
        ? state.messages.sublist(cut)
        : const <LocalChatMessage>[];
    final kept = cut >= 0 ? state.messages.sublist(0, cut) : state.messages;

    state = state.copyWith(
      messages: [
        ...kept,
        LocalChatMessage(
          message: ChatMessage(
            id: userId,
            threadId: baseThreadId,
            role: ChatMessageRole.user,
            content: content,
            status: ChatMessageStatus.complete,
            context: sentContext,
            createdAt: now,
          ),
          localAttachments: newAttachments,
          localReferences: references,
        ),
        LocalChatMessage(
          message: ChatMessage(
            id: assistantId,
            threadId: baseThreadId,
            role: ChatMessageRole.assistant,
            content: '',
            status: ChatMessageStatus.streaming,
            createdAt: now,
          ),
          stage: ChatStage.thinking,
        ),
      ],
      sending: true,
    );

    final stream = _ActiveStream();
    _stream = stream;
    final done = Completer<void>();
    stream.onFinished = () {
      if (!done.isCompleted) done.complete();
    };

    void patch(String id, LocalChatMessage Function(LocalChatMessage) update) {
      state = state.copyWith(
        messages: [for (final m in state.messages) m.id == id ? update(m) : m],
      );
    }

    void onEvent(ChatStreamEvent event) {
      switch (event) {
        case ChatMetaEvent():
          receivedMeta = true;
          final isNewThread = state.threadId != event.threadId;
          final oldUserId = userId, oldAssistantId = assistantId;
          userId = event.userMessageId;
          assistantId = event.assistantMessageId;
          state = state.copyWith(
            threadId: () => event.threadId,
            messages: [
              for (final m in state.messages)
                if (m.id == oldUserId)
                  LocalChatMessage(
                    message: m.message.copyWith(
                      id: userId,
                      threadId: event.threadId,
                    ),
                    localAttachments: m.localAttachments,
                    localReferences: m.localReferences,
                  )
                else if (m.id == oldAssistantId)
                  m.copyWith(
                    message: m.message.copyWith(
                      id: assistantId,
                      threadId: event.threadId,
                    ),
                  )
                else
                  m,
            ],
          );
          stream.assistantId = assistantId;
          if (isNewThread) unawaited(_refreshAttachments(event.threadId));
          // 返答のIDが届く前に停止が押されていた
          if (stream.stopRequested) {
            unawaited(_performStop(assistantId, stream));
          }
        case ChatStatusEvent():
          patch(
            assistantId,
            (m) => m.copyWith(
              stage: event.stage,
              searchDetail: event.detail,
              searchQuery: event.query,
              searchTarget: event.target,
              searchLayer: event.layer,
              searchHandle: event.handle,
            ),
          );
        case ChatSourcesEvent():
          patch(assistantId, (m) => m.copyWith(pendingSources: event.sources));
        case ChatAttachmentsEvent():
          // 全文で読む枠を超えて外した資料など(返答の下に知らせる。資料の一覧も読み直す)
          patch(
            assistantId,
            (m) => m.copyWith(
              message: m.message.copyWith(
                context: ChatMessageContext(attachmentNotice: event.notice),
              ),
            ),
          );
          unawaited(_refreshAttachments(state.threadId));
        case ChatThoughtEvent():
          patch(
            assistantId,
            (m) => m.copyWith(
              thoughtText: (m.thoughtText ?? '') + event.text,
            ),
          );
        case ChatDeltaEvent():
          patch(
            assistantId,
            (m) => m.copyWith(
              message: m.message.copyWith(
                content: m.message.content + event.text,
              ),
            ),
          );
        case ChatReplaceEvent():
          patch(
            assistantId,
            (m) => m.copyWith(message: m.message.copyWith(content: event.text)),
          );
        case ChatDoneEvent():
          patch(
            assistantId,
            (m) => m.copyWith(
              message: m.message.copyWith(
                status: event.status,
                citations: event.citations ?? const [],
                creditsChargedMicro: (event.creditsCharged * 1000000).round(),
              ),
              clearProgress: true,
            ),
          );
        case ChatErrorEvent():
          patch(
            assistantId,
            (m) => m.copyWith(
              message: m.message.copyWith(status: ChatMessageStatus.error),
              clearProgress: true,
            ),
          );
      }
    }

    void onFailure(Object error) {
      final code = error is ChatRequestException
          ? error.code
          : error is SessionExpiredException
          ? 'SESSION_EXPIRED'
          : 'NETWORK';
      final detail = error is ChatRequestException
          ? error.detail
          : const <String, dynamic>{};
      if (code == 'NETWORK' && receivedMeta) {
        // 受信中に切れた。サーバー側では生成が続いているので、DBで完了を待つ。
        unawaited(_waitForServerCompletion(assistantId, _generation));
        return;
      }
      // ストリームが始まる前に弾かれた(残高不足・送信頻度など)か、送信自体が届かなかった。
      // userメッセージはサーバーに保存されていないので、返答の枠を消して「送れなかった」表示にする。
      if (replaceFromMessageId != null) {
        // 編集は送る前に弾かれた: サーバーでは何も消えていないので、会話を元に戻す
        state = state.copyWith(
          messages: [
            ...state.messages.where(
              (m) => m.id != userId && m.id != assistantId,
            ),
            ...removed,
          ],
        );
        onRejected?.call(code, detail);
        return;
      }
      state = state.copyWith(
        messages: [
          for (final m in state.messages)
            if (m.id != assistantId)
              m.id == userId
                  ? m.copyWith(failed: (code: code, detail: detail))
                  : m,
        ],
      );
    }

    stream.subscription = _repo
        .sendMessage(request)
        .listen(
          onEvent,
          onError: (Object e) {
            onFailure(e);
            stream.finish();
          },
          onDone: stream.finish,
          cancelOnError: true,
        );

    await done.future;

    if (identical(_stream, stream)) _stream = null;
    state = state.copyWith(
      sending: false,
      // 返答のIDが届く前に終わった(送れなかった等)ので、待っていた停止は要らない
      stopping: stream.stopRequested && stream.assistantId == null
          ? false
          : state.stopping,
    );
    // 添付した資料の状態(確認済み・断った)と、AIが付けた名前を読み直す
    if ((newAttachments.isNotEmpty || references.isNotEmpty) && receivedMeta) {
      unawaited(_refreshAttachments(state.threadId));
    }
    // 次に開いたときに今の内容がすぐ出るよう、キャッシュを読み直す
    if (receivedMeta) _inBackground(_syncCache(state.threadId));
  }

  /// キャッシュだけをサーバーの内容で置き換える(表示中の状態は触らない)。
  Future<void> _syncCache(String? threadId) async {
    final uid = _uid;
    if (uid == null || threadId == null) return;
    try {
      await _cache.replaceMessages(
        uid,
        threadId,
        await _repo.fetchMessageRows(threadId),
      );
    } catch (_) {
      // キャッシュが古いだけ。次に開いたとき読み直す
    }
  }

  /// 送れなかったuserメッセージを取り除き、同じ内容でもう一度送る。
  Future<void> retry(String failedMessageId) async {
    final target = state.messages
        .where((m) => m.id == failedMessageId)
        .firstOrNull;
    if (target == null || target.failedCode == null || state.sending) return;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id != failedMessageId) m,
      ],
    );
    await send(
      target.message.content,
      context: target.message.context,
      newAttachments: target.localAttachments,
      references: target.localReferences,
    );
  }

  /// 送れなかったuserメッセージを画面から消す(入力欄に戻す等は呼び出し側で)。
  void discard(String failedMessageId) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id != failedMessageId) m,
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 停止
  // -------------------------------------------------------------------------

  /// 生成中の返答を止める。止めても送ったメッセージは残り、そのまま次を送れる。
  void stop() {
    final stream = _stream;
    if (stream == null || state.stopping) return;
    state = state.copyWith(stopping: true);
    final assistantId = stream.assistantId;
    if (assistantId == null) {
      stream.stopRequested = true;
      return;
    }
    unawaited(_performStop(assistantId, stream));
  }

  /// 停止のリクエストを送り、サーバーが止めたところまでで確定した行に差し替える。受信もここで止める
  /// (止めた後はサーバーも流さない)。確定した行が返るので、完了をDBで待つ必要は無い。
  Future<void> _performStop(String assistantId, _ActiveStream stream) async {
    _patch(assistantId, (m) => m.copyWith(stopping: true, stopFailed: false));
    try {
      final row = await _repo.stopMessage(assistantId);
      await stream.cancel();
      _patch(
        assistantId,
        (m) => LocalChatMessage(
          message: row,
          localAttachments: m.localAttachments,
          localReferences: m.localReferences,
        ),
      );
    } catch (_) {
      _patch(assistantId, (m) => m.copyWith(stopping: false, stopFailed: true));
    } finally {
      state = state.copyWith(stopping: false);
    }
  }

  // -------------------------------------------------------------------------
  // 裏から戻った・通信が切れた
  // -------------------------------------------------------------------------

  /// アプリが前面に戻ってきたとき(AppLifecycleState.resumed)に呼ぶ。裏に回している間に受信の接続が
  /// 切れていても、iOSはエラーにせず止まったままになることがあるので、受信中だった返答は受信をやめて、
  /// サーバーの内容を読み直して追いつく(サーバー側の生成・保存・課金は最後まで走っている)。
  Future<void> onAppResumed() async {
    final stream = _stream;
    final threadId = state.threadId;
    if (threadId == null) return;
    final streaming = [
      for (final m in state.messages)
        if (!m.isUser && m.isStreaming && !m.id.startsWith('local-')) m.id,
    ];
    if (stream == null && streaming.isEmpty) return;
    await stream?.cancel();
    final generation = _generation;
    for (final id in streaming) {
      unawaited(_waitForServerCompletion(id, generation));
    }
  }

  /// サーバー側の生成が終わるまでDBを見に行き、終わったら差し替える。
  Future<void> _waitForServerCompletion(
    String messageId,
    int generation,
  ) async {
    _patch(messageId, (m) => m.copyWith(reconnecting: true));
    for (var attempt = 0; attempt < chatReconnectPollMaxAttempts; attempt++) {
      await Future<void>.delayed(chatReconnectPollInterval);
      if (!ref.mounted || generation != _generation) return;
      try {
        final row = await _repo.getMessage(messageId);
        if (row != null && row.status != ChatMessageStatus.streaming) {
          _patch(
            messageId,
            (m) => LocalChatMessage(
              message: row,
              localAttachments: m.localAttachments,
              localReferences: m.localReferences,
            ),
          );
          _inBackground(_syncCache(state.threadId));
          return;
        }
      } catch (_) {
        // 一時的な読み取り失敗は次の試行に任せる
      }
    }
    if (!ref.mounted) return;
    _patch(
      messageId,
      (m) => m.copyWith(
        message: m.message.copyWith(status: ChatMessageStatus.error),
        reconnecting: false,
        clearProgress: true,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 資料
  // -------------------------------------------------------------------------

  /// 資料を外す。外したらAIにはもう渡らない(会話の中の「添付した」印は残る)。
  Future<void> removeAttachment(String attachmentId) async {
    await _repo.removeAttachment(attachmentId);
    state = state.copyWith(
      attachments: [
        for (final a in state.attachments)
          if (a.id != attachmentId) a,
      ],
    );
  }

  /// 資料を全文で読ませる/やめる。断られたら(上限など)元に戻して例外を投げる。
  Future<void> selectAttachment(String attachmentId, bool selected) async {
    ChatAttachment withSelected(ChatAttachment a, bool value) =>
        a.id != attachmentId
        ? a
        : ChatAttachment(
            id: a.id,
            threadId: a.threadId,
            messageId: a.messageId,
            kind: a.kind,
            status: a.status,
            title: a.title,
            content: a.content,
            charCount: a.charCount,
            tokenCount: a.tokenCount,
            selected: value,
            summary: a.summary,
            sections: a.sections,
            createdAt: a.createdAt,
            fileName: a.fileName,
            pageCount: a.pageCount,
          );
    state = state.copyWith(
      attachments: [
        for (final a in state.attachments) withSelected(a, selected),
      ],
    );
    try {
      await _repo.setAttachmentSelected(attachmentId, selected);
    } catch (_) {
      state = state.copyWith(
        attachments: [
          for (final a in state.attachments) withSelected(a, !selected),
        ],
      );
      rethrow;
    }
  }

  /// 資料の一覧をサーバーの内容で読み直す(ファイルを送る前に取り出した結果を反映するときなど)。
  Future<void> refreshAttachments() => _refreshAttachments(state.threadId);

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  /// 画面が待たなくてよい処理(キャッシュへの保存)を走らせる。失敗は握りつぶす
  /// (キャッシュが古いだけで、次に開いたときサーバーの内容で置き換わる)。
  void _inBackground(Future<void> work) {
    late final Future<void> tracked;
    tracked = work
        .catchError((Object _) {})
        .whenComplete(() => _background.remove(tracked));
    _background.add(tracked);
  }

  /// 裏で走らせている保存がすべて終わるのを待つ。テストで、DBを閉じる前に使う。
  @visibleForTesting
  Future<void> settle() async {
    while (_background.isNotEmpty) {
      await Future.wait(_background.toList());
    }
  }

  void _patch(String id, LocalChatMessage Function(LocalChatMessage) update) {
    if (!ref.mounted) return;
    state = state.copyWith(
      messages: [for (final m in state.messages) m.id == id ? update(m) : m],
    );
  }

  /// 今の受信をやめて、送信中の状態も戻す。
  Future<void> _detachStream() async {
    final stream = _stream;
    if (stream == null) return;
    _stream = null;
    await stream.cancel();
    state = state.copyWith(sending: false, stopping: false);
  }

  /// 送信中のスレッドが削除・名前変更されたなどで、今の会話を開き直さずに外したいとき。
  void clearConversation() {
    _generation++;
    unawaited(_stream?.cancel());
    _stream = null;
    state = const ChatConversationState();
  }
}

/// 今受信している返答1つ分の受信の状態。
class _ActiveStream {
  StreamSubscription<ChatStreamEvent>? subscription;
  void Function()? onFinished;

  /// metaイベントで届く返答のID。
  String? assistantId;
  bool stopRequested = false;
  bool _finished = false;

  void finish() {
    if (_finished) return;
    _finished = true;
    onFinished?.call();
  }

  /// 受信をやめる。接続が閉じるだけで、サーバー側の生成はそのまま走る。
  Future<void> cancel() async {
    await subscription?.cancel();
    finish();
  }
}
