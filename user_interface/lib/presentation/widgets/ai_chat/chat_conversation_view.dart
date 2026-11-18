// lib/presentation/widgets/ai_chat/chat_conversation_view.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_attachment_list_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_attachment_viewer.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_message_views.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/ai_chat/launch_gate_backdrop.dart';

/// 下端からこの距離以内にいるときだけ、新しい文字に合わせて自動で下へ追従する。
const _stickToBottomPx = 96.0;

/// 会話の画面を外から操作する(シートのヘッダーのクリップのボタンから、資料の一覧を開く)。
class ChatConversationController {
  VoidCallback? _openAttachmentList;

  /// この会話の資料の一覧を開く。会話の画面が出ていなければ何もしない。
  void openAttachmentList() => _openAttachmentList?.call();
}

/// 1つの会話の画面(webappのChatConversationと同じ構成): メッセージの一覧 → 入力欄。
/// 何も話していないときは「出発ゲート」(背景 + 文言 + 質問の候補)を出す。
///
/// 会話の状態は [chatConversationProvider] が持つ。この画面は表示と、送信前の組み立て
/// (選択した文章・見ているページ・編集の確認)だけを受け持つ。
class ChatConversationView extends ConsumerStatefulWidget {
  const ChatConversationView({
    super.key,
    required this.world,
    required this.onOpenCitation,
    this.onOpenLink,
    this.onBuyCredits,
    this.lectureId,
    this.lectureTitle,
    this.courseId,
    this.courseTitle,
    this.onDetachLecture,
    this.controller,
    this.selection,
    this.onClearSelection,
    this.screen,
  });

  final ChatWorld world;

  /// 出典を押したとき。specsは押された引用の区切り。
  final void Function(ChatCitation citation, List<String> specs) onOpenCitation;

  /// 回答の中のWebのリンクを開く(アプリ内ブラウザ)。
  final void Function(String url)? onOpenLink;

  /// クレジット不足のとき、プラン・購入の画面へ案内する。
  final VoidCallback? onBuyCredits;

  final ChatConversationController? controller;

  /// 話題にする講義。nullなら講義を指定しない。
  final String? lectureId;
  final String? lectureTitle;

  /// 話題にするコース(コースの画面から開いたとき。講義があるときは講義を優先して送らない)。
  final String? courseId;
  final String? courseTitle;

  /// 講義・コースのチップを外す。
  final VoidCallback? onDetachLecture;

  /// 「Ask」で添える選択。1回の送信にだけ添える。
  final ChatSelection? selection;
  final VoidCallback? onClearSelection;

  /// 今いる画面のページ。毎回の送信に添える(本文はバックエンドが読む)。
  final ChatScreenRef? screen;

  @override
  ConsumerState<ChatConversationView> createState() =>
      _ChatConversationViewState();
}

class _ChatConversationViewState extends ConsumerState<ChatConversationView> {
  final _scroll = ScrollController();
  bool _stickToBottom = true;

  /// 会話を開いた時点(と、あとから読み込んだ過去ログ)のメッセージ。基準点より上に並べ、
  /// それより後に増えたメッセージ(送った質問・受信中の回答)は基準点より下に並べる。
  /// 上は上へ、下は下へ伸びるので、過去ログが増えても回答が伸びても、読んでいる文章は動かない。
  Set<String> _historyIds = const {};

  /// 中身が画面からはみ出しているか。はみ出すまでは全部を基準点より上に並べる
  /// (基準点より下に何かあると、短い会話でもその分だけスクロールできてしまうため)。
  /// はみ出すまではスクロールできないので、読んでいる文章が流れることもない。
  bool _overflowing = false;

  /// 入力欄の中身を変える依頼。
  ChatPrefill? _prefill;

  /// 資料の一覧から、入力欄に資料を入れる・外す依頼。
  ChatInsertRequest? _insertRequest;

  /// 入力欄で指している既存の資料(一覧に「添付する予定」として見せる)。
  final _pendingRefs = ValueNotifier<List<ChatAttachmentRef>>(const []);

  /// 下の入力欄で直しているユーザーメッセージ。送ると、そのメッセージ自身と後ろが消えて、そこからやり直す。
  String? _editingId;

  /// 編集・作り直しが送る前に弾かれた(残高不足など)。会話は元のまま。
  ({String code, Map<String, dynamic> detail})? _editError;

  /// 会話の中のAIの回答を選んで「返信」したときの引用。「Ask」(selection)とは別に持ち、
  /// どちらかがあれば次の送信に添える(新しい「Ask」が来たら、そちらを優先して返信の引用は外す)。
  ChatSelection? _replySelection;

  ChatSelection? get _activeSelection => _replySelection ?? widget.selection;

  @override
  void initState() {
    super.initState();
    _historyIds = {
      for (final m in ref.read(chatConversationProvider).messages) m.id,
    };
    _scroll.addListener(_onScroll);
    widget.controller?._openAttachmentList = _openAttachmentList;
  }

  @override
  void didUpdateWidget(ChatConversationView old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) {
      old.controller?._openAttachmentList = null;
      widget.controller?._openAttachmentList = _openAttachmentList;
    }
    if (widget.selection != null && widget.selection != old.selection) {
      _replySelection = null;
    }
  }

  @override
  void dispose() {
    widget.controller?._openAttachmentList = null;
    _pendingRefs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _stickToBottom = p.maxScrollExtent - p.pixels < _stickToBottomPx;

    // 最上部(過去メッセージ側)に近づいたら過去ログを読み込む
    if (p.pixels - p.minScrollExtent <= 150) {
      final state = ref.read(chatConversationProvider);
      if (state.hasMore && !state.loadingOlder && !state.loading) {
        unawaited(_notifier.loadOlderMessages());
      }
    }
  }

  /// 最下部(最新の発言)へ合わせる。最下部は maxScrollExtent。新しい内容の高さは
  /// レイアウト後に決まるので、次のフレームで合わせる(最下部にいる間の追従は
  /// [_StickToBottomPhysics]がレイアウト中に行うので、ここは離れていたときだけ動く)。
  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.maxScrollExtent - p.pixels > 0.5) {
        _scroll.jumpTo(p.maxScrollExtent);
      }
    });
  }

  ChatConversation get _notifier => ref.read(chatConversationProvider.notifier);

  /// 入力欄に中身を入れる。[attachments]を渡すと(空でも)入力欄の新しい添付をそれに置き換える。
  void _setPrefill(
    String text, {
    List<ChatNewAttachment>? attachments,
    List<ChatAttachmentRef> references = const [],
  }) => setState(
    () => _prefill = ChatPrefill(
      text: text,
      attachments: attachments,
      references: references,
      nonce: DateTime.now().microsecondsSinceEpoch,
    ),
  );

  /// 送った資料を読む(外すこともできる)。
  void _openAttachment(ChatAttachment attachment) {
    unawaited(
      showChatAttachmentViewer(
        context,
        colors: ChatColors.of(widget.world),
        attachment: attachment,
        onRemove: attachment.status == ChatAttachmentStatus.ready
            ? () => _notifier.removeAttachment(attachment.id)
            : null,
      ),
    );
  }

  /// この会話の資料の一覧を開く。
  void _openAttachmentList() {
    unawaited(
      showChatAttachmentListSheet(
        context,
        colors: ChatColors.of(widget.world),
        pendingRefs: _pendingRefs,
        onAttach: (attachment, mode) => setState(
          () => _insertRequest = ChatInsertRequest(
            attachment: attachment,
            mode: mode,
            nonce: DateTime.now().microsecondsSinceEpoch,
          ),
        ),
        onView: _openAttachment,
        onPin: (attachment) => _notifier.selectAttachment(attachment.id, true),
        onUnpin: (attachment) => _notifier.selectAttachment(attachment.id, false),
      ),
    );
  }

  /// 全文で読むのをやめる(失敗しても会話は続けられる。次に開いたときサーバーの状態に戻る)。
  Future<void> _unselectAttachment(String id) async {
    try {
      await _notifier.selectAttachment(id, false);
    } catch (_) {}
  }

  void _clearSelection() {
    setState(() => _replySelection = null);
    widget.onClearSelection?.call();
  }

  // ---- 編集・作り直し(一本道) ----

  /// 編集中のメッセージの後ろ(消えるもの)の情報。
  ({Set<String> laterIds, int turns, List<ChatAttachment> doomedAttachments})?
  _editInfo(ChatConversationState state) {
    final id = _editingId;
    if (id == null) return null;
    final index = state.messages.indexWhere((m) => m.id == id);
    if (index < 0) return null;
    final later = state.messages.sublist(index + 1);
    final laterIds = {for (final m in later) m.id};
    return (
      laterIds: laterIds,
      turns: later.where((m) => m.isUser).length,
      doomedAttachments: [
        for (final a in state.attachments)
          if (a.messageId != null &&
              laterIds.contains(a.messageId) &&
              (a.status == ChatAttachmentStatus.ready ||
                  a.status == ChatAttachmentStatus.processing))
            a,
      ],
    );
  }

  /// 送るときに一緒に指す資料(このメッセージで添付・指した資料のうち、今も使えるもの)。
  List<ChatAttachmentRef> _referencesOf(
    LocalChatMessage message,
    ChatConversationState state,
  ) {
    final byId = {for (final a in state.attachments) a.id: a};
    return [
      for (final r in message.message.context.attachments)
        if (byId[r.attachmentId]?.status == ChatAttachmentStatus.ready) r,
    ];
  }

  /// 自分のメッセージを編集する: 本文と、指している資料を入力欄に読み込む
  /// (本文の資料の印は、入力欄が「@名前」に戻す)。
  void _startEdit(LocalChatMessage message, ChatConversationState state) {
    if (state.sending) return;
    setState(() {
      _editingId = message.id;
      _editError = null;
      _replySelection = _restoreQuote(message.message.context);
    });
    _setPrefill(
      message.message.content,
      attachments: const [],
      references: _referencesOf(message, state),
    );
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editError = null;
      _replySelection = null;
    });
    _setPrefill('', attachments: const []);
  }

  /// 送ったときの文脈から、入力欄の引用(選択・返信)を戻す。
  ChatSelection? _restoreQuote(ChatMessageContext context) =>
      context.selectedText == null
      ? null
      : ChatSelection(
          text: context.selectedText!,
          screen: context.screen,
          replyToMessageId: context.replyToMessageId,
        );

  /// 最後の回答を作り直す: 直前の質問を、同じ内容で編集して送る(その質問と回答を消して、新しい往復を書く)。
  /// 作り直せるのは最後の回答だけ(途中の回答を作り直すと後ろの会話の前提が崩れるので、それは質問の編集で行う)。
  VoidCallback? _regenerateFor(
    int assistantIndex,
    ChatConversationState state,
  ) {
    if (state.sending ||
        _editingId != null ||
        assistantIndex != state.messages.length - 1) {
      return null;
    }
    final target = state.messages[assistantIndex];
    const allowed = {
      ChatMessageStatus.complete,
      ChatMessageStatus.stopped,
      ChatMessageStatus.error,
    };
    if (!allowed.contains(target.message.status)) return null;
    final previousUser = state.messages
        .sublist(0, assistantIndex)
        .reversed
        .where((m) => m.isUser)
        .firstOrNull;
    if (previousUser == null || previousUser.id.startsWith('local-')) {
      return null;
    }
    return () {
      _stickToBottom = true;
      setState(() => _editError = null);
      unawaited(
        _notifier.send(
          previousUser.message.content,
          context: previousUser.message.context,
          references: _referencesOf(previousUser, state),
          replaceFromMessageId: previousUser.id,
          onRejected: (code, detail) {
            if (mounted) {
              setState(() => _editError = (code: code, detail: detail));
            }
          },
        ),
      );
    };
  }

  // ---- 送信 ----

  ChatMessageContext _contextForSend() {
    final selection = _activeSelection;
    return ChatMessageContext(
      lectureId: widget.lectureId,
      courseId: widget.lectureId == null ? widget.courseId : null,
      // 選んだページ(「Ask」)を優先し、無ければ今いる画面のページ
      screen: selection?.screen ?? widget.screen,
      selectedText: selection?.text,
      selectionBefore: selection?.before,
      selectionAfter: selection?.after,
      replyToMessageId: selection?.replyToMessageId,
    );
  }

  Future<void> _handleSend(
    String content,
    List<ChatNewAttachment> attachments,
    List<ChatAttachmentRef> references,
    ChatConversationState state,
  ) async {
    _stickToBottom = true;
    final context = _contextForSend();
    // 選択した文章は1回の質問にだけ添える
    if (_activeSelection != null) _clearSelection();

    final editingId = _editingId;
    if (editingId == null) {
      unawaited(
        _notifier.send(
          content,
          context: context,
          newAttachments: attachments,
          references: references,
        ),
      );
      return;
    }
    final info = _editInfo(state);

    // 後ろで添付した資料も消えるときだけ、送る前に確かめる(往復が消えることは入力欄の上の帯に出ている)
    if (info != null && info.doomedAttachments.isNotEmpty) {
      final ok = await _confirmEdit(info.turns, info.doomedAttachments);
      if (!mounted) return;
      if (!ok) {
        // 入力欄は送ったときに空になっているので、書いたものを戻す
        _setPrefill(content, attachments: attachments, references: references);
        setState(() => _replySelection = _restoreQuote(context));
        return;
      }
    }
    setState(() {
      _editingId = null;
      _editError = null;
    });
    unawaited(
      _notifier.send(
        content,
        context: context,
        newAttachments: attachments,
        references: references,
        replaceFromMessageId: editingId,
        onRejected: (code, detail) {
          // 送る前に弾かれた: 会話は元のままなので、入力欄を編集中に戻す
          if (!mounted) return;
          setState(() {
            _editingId = editingId;
            _editError = (code: code, detail: detail);
            _replySelection = _restoreQuote(context);
          });
          _setPrefill(
            content,
            attachments: attachments,
            references: references,
          );
        },
      ),
    );
  }

  Future<bool> _confirmEdit(int turns, List<ChatAttachment> doomed) async {
    final l10n = AppLocalizations.of(context);
    final titles = [
      for (final a in doomed)
        '「${a.title ?? a.fileName ?? l10n.aiChatAttachmentUntitled}」',
    ].join();
    final colors = ChatColors.of(widget.world);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: colors.menuBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.aiChatEditConfirmTitle,
          style: TextStyle(color: colors.strongText, fontSize: 17),
        ),
        content: Text(
          l10n.aiChatEditConfirmBody('$turns', titles),
          style: TextStyle(color: colors.text, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              MaterialLocalizations.of(context).cancelButtonLabel,
              style: TextStyle(color: colors.actionForeground),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.aiChatEditConfirmSend,
              style: TextStyle(color: colors.danger),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---- 表示 ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ChatColors.of(widget.world);
    final state = ref.watch(chatConversationProvider);

    // 新しい文字・メッセージが来たら、下端にいるときだけ追従する(過去ログ読み込み時は飛ばさない)
    ref.listen(chatConversationProvider, (previous, next) {
      if (previous == null) return;
      // 会話を開いた・読み直した・新しい会話にした: そのときのメッセージをすべて基準点より上へ。
      // (最初の送信でthreadIdが決まるのは同じ会話の続きなので、ここでは見ない)
      final reopened = previous.loading != next.loading ||
          (next.threadId == null &&
              next.messages.isEmpty &&
              previous.messages.isNotEmpty);
      if (reopened) {
        _historyIds = {for (final m in next.messages) m.id};
        _overflowing = false;
        _stickToBottom = true;
        _scrollToBottomSoon();
        return;
      }
      // 編集・作り直しでメッセージが消えた: いったん全部を基準点より上に戻して、
      // はみ出しているかを測り直す(送ったときの仮のIDが本物に変わるのは消えたとみなさない)。
      final nextIds = {for (final m in next.messages) m.id};
      final removed = previous.messages.any(
        (m) => !m.id.startsWith('local-') && !nextIds.contains(m.id),
      );
      if (removed) {
        _historyIds = nextIds;
        _overflowing = false;
      }
      final prevMsgs = previous.messages;
      final nextMsgs = next.messages;
      if (_stickToBottom && prevMsgs != nextMsgs) {
        final isPrepend = prevMsgs.isNotEmpty &&
            nextMsgs.isNotEmpty &&
            nextMsgs.first.id != prevMsgs.first.id;
        if (!isPrepend) {
          _scrollToBottomSoon();
        }
      }
    });

    final selectedText = _activeSelection?.text;
    final selectedTooLong =
        (selectedText?.length ?? 0) > chatMaxSelectedTextChars;
    final editInfo = _editInfo(state);
    final attachmentsById = {for (final a in state.attachments) a.id: a};
    final attachmentsByMessage = <String, List<ChatAttachment>>{};
    for (final a in state.attachments) {
      final id = a.messageId;
      if (id != null) (attachmentsByMessage[id] ??= []).add(a);
    }

    final showGate =
        !state.loading && !state.loadFailed && state.messages.isEmpty;
    // 前回の内容(端末のキャッシュ)があれば、読み込み中もそれを見せる
    final showSkeleton = state.loading && state.messages.isEmpty;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (showGate)
                Positioned.fill(child: LaunchGateBackdrop(world: widget.world)),
              Positioned.fill(
                child: showSkeleton
                    ? _LoadingSkeleton(colors: colors)
                    : state.loadFailed
                    ? _LoadFailed(
                        colors: colors,
                        onRetry: () => unawaited(_notifier.reload()),
                      )
                    : showGate
                    ? _Gate(
                        colors: colors,
                        suggestions: _suggestions(l10n, selectedText != null),
                        onPick: _setPrefill,
                      )
                    : NotificationListener<ScrollMetricsNotification>(
                        onNotification: _onListMetrics,
                        child: _MessageList(
                          controller: _scroll,
                          messages: _splitLive(
                            _buildMessages(
                              state,
                              colors,
                              attachmentsById,
                              attachmentsByMessage,
                              editInfo,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editError != null)
                _Banner(
                  colors: colors,
                  text: chatFailureCopy(
                    l10n,
                    _editError!.code,
                    _editError!.detail,
                  ).text,
                  actions: [
                    _BannerAction(
                      label: l10n.aiChatDismiss,
                      colors: colors,
                      onTap: () => setState(() => _editError = null),
                    ),
                  ],
                ),
              if (selectedTooLong)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.aiChatErrorSelectedTooLong(
                      '$chatMaxSelectedTextChars',
                    ),
                    style: TextStyle(color: colors.danger, fontSize: 12.5),
                  ),
                ),
              ChatComposer(
                colors: colors,
                placeholder: state.messages.isNotEmpty
                    ? l10n.aiChatInputPlaceholderFollowUp
                    : l10n.aiChatInputPlaceholder,
                disabled: state.sending || selectedTooLong,
                onStop: state.sending ? _notifier.stop : null,
                stopping: state.stopping,
                prefill: _prefill,
                editingLabel: editInfo == null
                    ? null
                    : editInfo.turns == 0
                    ? l10n.aiChatEditingLast
                    : editInfo.doomedAttachments.isNotEmpty
                    ? l10n.aiChatEditingWithAttachments(
                        '${editInfo.turns}',
                        '${editInfo.doomedAttachments.length}',
                      )
                    : l10n.aiChatEditing('${editInfo.turns}'),
                onCancelEdit: _cancelEdit,
                selectedText: selectedText,
                onClearSelectedText: _clearSelection,
                lectureTitle: widget.lectureId == null
                    ? null
                    : widget.lectureTitle,
                courseTitle:
                    widget.lectureId == null && widget.courseId != null
                    ? widget.courseTitle
                    : null,
                onDetachLecture: widget.onDetachLecture,
                onSend: (content, attachments, references) => unawaited(
                  _handleSend(content, attachments, references, state),
                ),
                selectedAttachments: [
                  for (final a in state.attachments)
                    if (a.selected &&
                        a.kind != 'image' &&
                        (a.status == ChatAttachmentStatus.ready ||
                            a.status == ChatAttachmentStatus.processing))
                      a,
                ],
                onUnselectAttachment: (id) =>
                    unawaited(_unselectAttachment(id)),
                // 編集中は、送ると消える資料を指せないようにする
                mentionables: [
                  for (final a in state.attachments)
                    if (a.status == ChatAttachmentStatus.ready &&
                        !(editInfo != null &&
                            a.messageId != null &&
                            editInfo.laterIds.contains(a.messageId)))
                      a,
                ],
                onViewAttachment: (id) {
                  final a = attachmentsById[id];
                  if (a != null) _openAttachment(a);
                },
                insertRequest: _insertRequest,
                onPendingChange: (refs) => _pendingRefs.value = refs,
                onOpenAttachmentList: _openAttachmentList,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.aiChatAiDisclaimer,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.hintText, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// はみ出すまでは、liveもhistoryの続きとして基準点より上に並べる。
  ({List<Widget> history, List<Widget> live}) _splitLive(
    ({List<Widget> history, List<Widget> live}) built,
  ) => _overflowing
      ? built
      : (history: [...built.history, ...built.live], live: const <Widget>[]);

  /// 全部が基準点より上にある間は、minScrollExtent < 0 が「画面からはみ出した」の意味。
  /// はみ出したら次のフレームでliveを基準点より下へ移す(最下部にいるので見た目は変わらない)。
  bool _onListMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0 && !_overflowing && n.metrics.minScrollExtent < -0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_overflowing) setState(() => _overflowing = true);
      });
    }
    return false;
  }

  List<String> _suggestions(AppLocalizations l10n, bool hasSelection) {
    if (hasSelection) return [l10n.aiChatSuggestionSelection];
    if (widget.lectureId != null) {
      return [l10n.aiChatSuggestionThisLecture, l10n.aiChatSuggestionQuiz];
    }
    return [
      l10n.aiChatSuggestionLatest,
      l10n.aiChatSuggestionQuiz,
      l10n.aiChatSuggestionGoals,
    ];
  }

  /// 一覧に並べるウィジェット。[_historyIds]に入っている最後のメッセージまでが
  /// history(基準点より上)、それより後がlive(基準点より下)。
  ({List<Widget> history, List<Widget> live}) _buildMessages(
    ChatConversationState state,
    ChatColors colors,
    Map<String, ChatAttachment> attachmentsById,
    Map<String, List<ChatAttachment>> attachmentsByMessage,
    ({Set<String> laterIds, int turns, List<ChatAttachment> doomedAttachments})?
    editInfo,
  ) {
    final l10n = AppLocalizations.of(context);
    final out = <Widget>[];
    if (state.loadingOlder) {
      out.add(_OlderLoadingIndicator(colors: colors));
    }
    final lastHistory = state.messages.lastIndexWhere(
      (m) => _historyIds.contains(m.id),
    );
    var liveStart = out.length;
    for (var i = 0; i < state.messages.length; i++) {
      final message = state.messages[i];
      final editState = message.id == _editingId
          ? ChatEditState.target
          : (editInfo?.laterIds.contains(message.id) ?? false)
          ? ChatEditState.doomed
          : null;
      if (message.isUser) {
        out.add(
          ChatUserMessage(
            message: message,
            colors: colors,
            attachments: attachmentsByMessage[message.id] ?? const [],
            attachmentsById: attachmentsById,
            onOpenAttachment: _openAttachment,
            onEdit:
                !state.sending &&
                    message.failedCode == null &&
                    !message.id.startsWith('local-')
                ? () => _startEdit(message, state)
                : null,
            editState: editState,
          ),
        );
        final failedCode = message.failedCode;
        if (failedCode != null) {
          final copy = chatFailureCopy(l10n, failedCode, message.failedDetail);
          out.add(
            _Banner(
              colors: colors,
              text: copy.text,
              actions: [
                if (copy.buyCredits && widget.onBuyCredits != null)
                  _BannerAction(
                    label: l10n.aiChatBuyCredits,
                    colors: colors,
                    primary: true,
                    onTap: widget.onBuyCredits!,
                  )
                else if (!copy.buyCredits && copy.canRetry)
                  _BannerAction(
                    label: l10n.aiChatResend,
                    colors: colors,
                    primary: true,
                    onTap: () => unawaited(_notifier.retry(message.id)),
                  ),
                _BannerAction(
                  label: l10n.aiChatDismiss,
                  colors: colors,
                  onTap: () {
                    _notifier.discard(message.id);
                    _setPrefill(
                      message.message.content,
                      attachments: message.localAttachments,
                      references: message.localReferences,
                    );
                  },
                ),
              ],
            ),
          );
        }
      } else {
        final question = state.messages
            .sublist(0, i)
            .reversed
            .where((m) => m.isUser)
            .firstOrNull
            ?.message
            .content;
        out.add(
          ChatAssistantMessage(
            message: message,
            world: widget.world,
            colors: colors,
            attachmentsById: attachmentsById,
            question: question,
            onResend: message.message.status == ChatMessageStatus.error
                ? _regenerateFor(i, state)
                : null,
            onRegenerate: _regenerateFor(i, state),
            onReplyToSelection: (selection) =>
                setState(() => _replySelection = selection),
            onCitationTap: widget.onOpenCitation,
            onOpenLink: widget.onOpenLink,
            editState: editState,
          ),
        );
      }
      if (i == lastHistory) liveStart = out.length;
    }
    return (history: out.sublist(0, liveStart), live: out.sublist(liveStart));
  }
}

/// メッセージの一覧。基準点(center)を画面の下端(anchor: 1.0)に置き、
/// - history(会話を開いた時点のメッセージと、あとから読み込む過去ログ)は基準点から上へ、
/// - live(その場で送った質問・受信中の回答)は基準点から下へ
/// 並べる。どちらも基準点から遠ざかる向きに伸びるので、過去ログを読み込んでも
/// 回答が伸びても、読んでいる文章の画面上の位置は変わらない。
/// 開いた直後はliveが空で、pixels: 0(=maxScrollExtent)が最下部。
class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller, required this.messages});

  final ScrollController controller;
  final ({List<Widget> history, List<Widget> live}) messages;

  static const _centerKey = ValueKey('chat-live');
  static const _gap = 18.0;
  static const _side = 16.0;
  static const _bottom = 12.0;

  /// 各メッセージの上に間隔を取る(一番上の余白も兼ねる)。
  static Widget _item(Widget child) => Padding(
    padding: const EdgeInsets.only(top: _gap),
    child: Align(
      alignment: Alignment.topCenter,
      // 広い画面(タブレット)でも読みやすい幅にする
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final history = messages.history;
    final live = messages.live;
    return CustomScrollView(
      controller: controller,
      center: _centerKey,
      anchor: 1.0,
      physics: const _StickToBottomPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // 基準点より前のsliverは上へ伸びる: index 0 が基準点のすぐ上(historyの最後)。
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            _side,
            0,
            _side,
            live.isEmpty ? _bottom : 0,
          ),
          sliver: SliverList.builder(
            itemCount: history.length,
            itemBuilder: (_, i) => _item(history[history.length - 1 - i]),
          ),
        ),
        SliverPadding(
          key: _centerKey,
          padding: EdgeInsets.fromLTRB(
            _side,
            0,
            _side,
            live.isEmpty ? 0 : _bottom,
          ),
          sliver: SliverList.builder(
            itemCount: live.length,
            itemBuilder: (_, i) => _item(live[i]),
          ),
        ),
      ],
    );
  }
}

/// 最下部(最新の発言)にいるときは、文字が増えても最下部に留まる。最下部は maxScrollExtent。
/// レイアウト中に合わせるので、伸びた回答が一瞬ずれて見えることはない。
class _StickToBottomPhysics extends ScrollPhysics {
  const _StickToBottomPhysics({super.parent});

  @override
  _StickToBottomPhysics applyTo(ScrollPhysics? ancestor) =>
      _StickToBottomPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    // oldPositionは最後にレイアウトした時点の位置。指が1フレームの間に動いて離れると
    // (間にレイアウトが入らないと)古いまま最下部に残るので、今の位置も最下部かを見る。
    // 見ないと、ユーザーが上へ動かした分が最下部へ戻されてしまう。
    final bottom = oldPosition.maxScrollExtent - 1.0;
    final wasAtBottom =
        oldPosition.pixels >= bottom && newPosition.pixels >= bottom;
    if (!isScrolling && velocity == 0 && wasAtBottom) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

/// 過去メッセージ読み込み中に最上部に表示するインジケーター。
class _OlderLoadingIndicator extends StatelessWidget {
  const _OlderLoadingIndicator({required this.colors});

  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(colors.hintText),
          ),
        ),
      ),
    );
  }
}

/// 何も話していないときの出発ゲート: 背景は[LaunchGateBackdrop]で、その上に文言と質問の候補が
/// 下から順に現れる。
class _Gate extends StatelessWidget {
  const _Gate({
    required this.colors,
    required this.suggestions,
    required this.onPick,
  });

  final ChatColors colors;
  final List<String> suggestions;
  final void Function(String text) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Rise(
              delay: 150,
              child: Text(
                'AI CHAT',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 10,
                  letterSpacing: 2.6,
                  fontFamily: 'Orbitron',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Rise(
              delay: 250,
              child: Text(
                l10n.aiChatEmptyTitle,
                style: TextStyle(
                  color: colors.strongText,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.38,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Rise(
              delay: 350,
              child: Text(
                l10n.aiChatEmptySubtitle,
                style: TextStyle(
                  color: colors.stageText,
                  fontSize: 12.5,
                  height: 1.65,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < suggestions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _Rise(
                  delay: 500 + i * 80,
                  child: InkWell(
                    onTap: () => onPick(suggestions[i]),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colors.quoteBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.inputBorder),
                      ),
                      child: Text(
                        suggestions[i],
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 下から少し上がりながら現れる(開くたびに、文字と候補が順に現れる)。
class _Rise extends StatelessWidget {
  const _Rise({required this.delay, required this.child});

  /// 待つミリ秒
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 750 + delay),
      curve: Interval(
        delay / (750 + delay),
        1,
        curve: const Cubic(.2, .7, .2, 1),
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton({required this.colors});

  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, {bool right = false, double height = 40}) =>
        Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: colors.quoteBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.inputBorder),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          bar(.55, right: true),
          const SizedBox(height: 18),
          bar(.95, height: 84),
          const SizedBox(height: 12),
          bar(.6),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.colors, required this.onRetry});

  final ChatColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.aiChatLoadFailed,
            style: TextStyle(color: colors.text, fontSize: 14),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: onRetry,
            child: Text(
              MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// 送る前に止められたときの理由と次の行動。
class _Banner extends StatelessWidget {
  const _Banner({
    required this.colors,
    required this.text,
    required this.actions,
  });

  final ChatColors colors;
  final String text;
  final List<_BannerAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.noticeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.noticeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: colors.noticeText,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: actions),
          ],
        ],
      ),
    );
  }
}

class _BannerAction extends StatelessWidget {
  const _BannerAction({
    required this.label,
    required this.colors,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final ChatColors colors;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: primary ? colors.accent : Colors.transparent,
          border: Border.all(
            color: primary ? colors.accent : colors.inputBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? Colors.white : colors.text,
            fontSize: 12.5,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
