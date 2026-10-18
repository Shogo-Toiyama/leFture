// lib/presentation/widgets/ai_chat/chat_composer.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_drafts.dart';
import 'package:lefture/core/utils/chat_composer_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_picker.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';

/// 入力欄に中身を入れる依頼(質問の候補を押した・編集を始めた・送れなかった送信を戻す)。
/// [nonce]が変わるたびに、同じ中身でも入れ直す。
///
/// [text]の資料の印(⟦att:id⟧)は「@名前」に戻る。[attachments]が渡されたとき(空でも)は、入力欄の
/// 新しい添付をこれに置き換える(渡さなければ触らない)。[references]はこの会話の既存の資料の渡し方。
class ChatPrefill {
  const ChatPrefill({
    required this.text,
    required this.nonce,
    this.attachments,
    this.references = const [],
  });

  final String text;
  final int nonce;
  final List<ChatNewAttachment>? attachments;
  final List<ChatAttachmentRef> references;
}

enum ChatInsertMode { full, mention, remove }

/// 資料の一覧から、入力欄に資料を入れる・外す依頼([nonce]が変わるたびに)。
class ChatInsertRequest {
  const ChatInsertRequest({
    required this.attachment,
    required this.mode,
    required this.nonce,
  });

  final ChatAttachment attachment;
  final ChatInsertMode mode;
  final int nonce;
}

/// 会話の下の入力欄。
///
/// スマホではEnterは改行で、送るのは送信ボタンだけ(日本語の変換の確定でEnterを押して、
/// 送ってしまう事故を避けるため。webappはEnterで送信)。生成中は送信ボタンが停止ボタンになる。
/// 「＋」から カメラ / 写真 / ファイル / 長い文章 / この会話の資料 を添える。資料は「@名前」で文中の
/// どこを指すかも伝えられる(打ち込むと候補が出る)。
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.colors,
    required this.onSend,
    required this.placeholder,
    this.onStop,
    this.stopping = false,
    this.disabled = false,
    this.prefill,
    this.editingLabel,
    this.onCancelEdit,
    this.selectedText,
    this.onClearSelectedText,
    this.lectureTitle,
    this.onDetachLecture,
    this.selectedAttachments = const [],
    this.onUnselectAttachment,
    this.mentionables = const [],
    this.onOpenAttachmentList,
    this.insertRequest,
    this.onPendingChange,
    this.onViewAttachment,
  });

  final ChatColors colors;

  /// 送る。空・空白だけで、資料も無いときは呼ばれない。本文の「@名前」は資料の印に置き換え済み。
  /// attachmentsはこの送信で新しく添える資料(いつも全文)、referencesはこの会話の既存の資料を指したもの。
  final void Function(
    String content,
    List<ChatNewAttachment> attachments,
    List<ChatAttachmentRef> references,
  )
  onSend;
  final String placeholder;

  /// 渡されていれば(=生成中)、送信ボタンの代わりに停止ボタンを出す。
  final VoidCallback? onStop;
  final bool stopping;

  /// 送れない状態(選択した文章が長すぎるなど)。
  final bool disabled;
  final ChatPrefill? prefill;

  /// 編集中の案内(「このメッセージを直しています…」)と、やめるボタン。
  final String? editingLabel;
  final VoidCallback? onCancelEdit;

  /// 「Ask」・返信で添える選択した文章。1回の送信にだけ添える。
  final String? selectedText;
  final VoidCallback? onClearSelectedText;

  /// 話題にしている講義(外せる)。
  final String? lectureTitle;
  final VoidCallback? onDetachLecture;

  /// 全文で読んでいる資料(チップで見せ、×で全文で読むのをやめられる)。
  final List<ChatAttachment> selectedAttachments;
  final void Function(String attachmentId)? onUnselectAttachment;

  /// この会話の使える資料(@の候補・「この会話の資料」)。
  final List<ChatAttachment> mentionables;
  final VoidCallback? onOpenAttachmentList;

  /// 資料の一覧から入れる・外す資料。
  final ChatInsertRequest? insertRequest;

  /// 入力欄で指している既存の資料が変わったとき(資料の一覧に「添付する予定」を見せるため)。
  final void Function(List<ChatAttachmentRef> refs)? onPendingChange;

  /// 送った資料の中身を見る(「@名前」の操作から)。
  final void Function(String attachmentId)? onViewAttachment;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

/// 「@名前」の部分に色を付ける入力欄の中身(文字の幅は変えない)。変換中は色を付けない。
class _MentionTextController extends TextEditingController {
  List<ComposerMention> mentions = const [];
  ChatColors colors = ChatColors.universe;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = withComposing && value.composing.isValid;
    if (mentions.isEmpty || composing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <InlineSpan>[];
    var pos = 0;
    for (final r in mentionRanges(text, mentions)) {
      if (r.start > pos) children.add(TextSpan(text: text.substring(pos, r.start)));
      final target = r.mention.target;
      final full =
          target is DraftMention ||
          (target is ExistingMention && target.mode == ChatAttachmentMode.full);
      children.add(
        TextSpan(
          text: text.substring(r.start, r.end),
          style: TextStyle(
            backgroundColor: full ? colors.mentionFull : colors.mentionRef,
          ),
        ),
      );
      pos = r.end;
    }
    if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: children);
  }
}

/// 入力の変化を直す: 長い貼り付けは入力欄に入れずに資料へ回し、「@名前」の途中の削除は名前ごと消す。
class _ComposerFormatter extends TextInputFormatter {
  _ComposerFormatter({
    required this.mentions,
    required this.canDivert,
    required this.onLongPaste,
  });

  final List<ComposerMention> Function() mentions;
  final bool Function() canDivert;
  final void Function(String pasted) onLongPaste;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 貼り付け(1度に2文字以上が入った)でメッセージの上限を超えるなら、資料の編集へ回す
    if (newValue.text.length > chatMaxMessageChars &&
        newValue.text.length - oldValue.text.length > 1 &&
        canDivert()) {
      final pasted = insertedText(oldValue.text, newValue.text);
      scheduleMicrotask(() => onLongPaste(pasted));
      return oldValue;
    }
    final fixed = removeBrokenMention(
      oldValue.text,
      newValue.text,
      mentions(),
    );
    if (fixed != null) {
      return TextEditingValue(
        text: fixed.text,
        selection: TextSelection.collapsed(offset: fixed.caret),
      );
    }
    return newValue;
  }
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = _MentionTextController();
  final _focus = FocusNode();
  late final ChatDraftsController _drafts;
  final _menuKey = GlobalKey();

  var _mentions = <ComposerMention>[];
  ComposerNoticeView? _notice;

  /// 「@」の候補(@の位置と、@の後ろに打った言葉)
  ({int start, String query})? _picker;

  /// カーソルが「@名前」の中にあるとき、その名前
  String? _activeLabel;
  int _caret = 0;
  List<ChatAttachmentRef> _lastPending = const [];

  @override
  void initState() {
    super.initState();
    _drafts = ChatDraftsController(
      pipeline: ref.read(chatFilePipelineProvider),
      repository: ref.read(chatRepositoryProvider),
    )..addListener(_onDraftsChanged);
    _controller
      ..colors = widget.colors
      ..addListener(_onControllerChanged);
    // 言葉の取り出しにcontextを使うので、最初の描画のあとに入れる
    if (widget.prefill != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPrefill();
      });
    }
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    _controller.colors = widget.colors;
    if (widget.prefill != null && widget.prefill?.nonce != old.prefill?.nonce) {
      _applyPrefill();
    }
    final req = widget.insertRequest;
    if (req != null && req.nonce != old.insertRequest?.nonce) {
      _applyInsertRequest(req);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _drafts
      ..removeListener(_onDraftsChanged)
      ..dispose();
    super.dispose();
  }

  void _onDraftsChanged() {
    if (mounted) setState(() {});
  }

  // ---- 文字と「@名前」 ----

  void _setMentions(List<ComposerMention> next) {
    _mentions = next;
    _controller.mentions = next;
  }

  void _setText(String text, {int? caret}) {
    final offset = (caret ?? text.length).clamp(0, text.length);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _caret = offset;
  }

  void _onControllerChanged() {
    final sel = _controller.selection;
    if (sel.isValid) _caret = sel.baseOffset;
    final text = _controller.text;
    String? active;
    ({int start, String query})? picker;
    if (sel.isValid && sel.isCollapsed) {
      for (final r in mentionRanges(text, _mentions)) {
        if (r.start < sel.baseOffset && sel.baseOffset < r.end) {
          active = r.mention.label;
          break;
        }
      }
      if (widget.mentionables.isNotEmpty) {
        picker = findMentionQuery(text, sel.baseOffset, [
          for (final m in _mentions) m.label,
        ]);
      }
    }
    if (active != _activeLabel || picker != _picker) {
      setState(() {
        _activeLabel = active;
        _picker = picker;
      });
    } else {
      // 文字数の表示・送信ボタンの有効/無効が変わる
      setState(() {});
    }
    _reportPending();
  }

  void _reportPending() {
    final refs = existingReferences(presentMentions(_controller.text, _mentions));
    bool same(List<ChatAttachmentRef> a, List<ChatAttachmentRef> b) =>
        a.length == b.length &&
        [
          for (var i = 0; i < a.length; i++)
            a[i].attachmentId == b[i].attachmentId && a[i].mode == b[i].mode,
        ].every((x) => x);
    if (same(refs, _lastPending)) return;
    _lastPending = refs;
    final cb = widget.onPendingChange;
    if (cb != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(refs);
      });
    }
  }

  /// カーソルの位置([range]があればその範囲)に文字を入れる。前の文字とくっつかないように空白を挟む。
  void _insertAtCaret(String text, {TextRange? range}) {
    final current = _controller.text;
    final start = (range?.start ?? _caret).clamp(0, current.length);
    final end = (range?.end ?? start).clamp(start, current.length);
    final lead = start > 0 && !RegExp(r'\s').hasMatch(current[start - 1])
        ? ' '
        : '';
    final next = current.substring(0, start) + lead + text + current.substring(end);
    _setText(next, caret: start + lead.length + text.length);
  }

  /// 資料を指す「@名前」を入れる(重複して指すときは同じ名前を使う)。
  void _addMention(MentionTarget target, String title, {TextRange? range}) {
    final same = _mentions.where((m) {
      final t = m.target;
      return t is ExistingMention && target is ExistingMention
          ? t.attachmentId == target.attachmentId
          : t is DraftMention && target is DraftMention
          ? t.localId == target.localId
          : false;
    }).firstOrNull;
    String label;
    if (same != null) {
      label = same.label;
      // 同じ資料を別の渡し方で入れ直したら、その渡し方にそろえる(既に文中にあれば、もう一度は入れない)
      if (target is ExistingMention && same.target is ExistingMention) {
        _setMentions([
          for (final m in _mentions) m == same ? m.withTarget(target) : m,
        ]);
        if (_controller.text.contains(label) && range == null) {
          setState(() {});
          return;
        }
      }
    } else {
      label = makeMentionLabel(title, [for (final m in _mentions) m.label]);
      _setMentions([
        ..._mentions,
        ComposerMention(label: label, target: target),
      ]);
    }
    _insertAtCaret('$label ', range: range);
  }

  void _removeLabelFromText(String label) {
    final next = _controller.text
        .split('$label ')
        .join()
        .split(label)
        .join();
    _setText(next, caret: _caret);
  }

  void _removeMention(ComposerMention mention) {
    final target = mention.target;
    if (target is DraftMention && _drafts.draftById(target.localId) != null) {
      _removeDraft(target.localId);
      return;
    }
    _removeLabelFromText(mention.label);
    _setMentions([
      for (final m in _mentions)
        if (m != mention) m,
    ]);
    setState(() => _activeLabel = null);
  }

  void _removeDraft(String localId) {
    final mention = _mentions
        .where(
          (m) => m.target is DraftMention &&
              (m.target as DraftMention).localId == localId,
        )
        .firstOrNull;
    _drafts.remove(localId);
    if (mention != null) {
      _removeLabelFromText(mention.label);
      _setMentions([
        for (final m in _mentions)
          if (m != mention) m,
      ]);
    }
    setState(() => _activeLabel = null);
  }

  /// 既存の資料の渡し方を切り替える(全文で添付 ⇄ メンション)。
  void _toggleMentionMode(ComposerMention mention) {
    final target = mention.target;
    if (target is! ExistingMention) return;
    final next = target.withMode(
      target.mode == ChatAttachmentMode.full
          ? ChatAttachmentMode.mention
          : ChatAttachmentMode.full,
    );
    _setMentions([
      for (final m in _mentions) m == mention ? m.withTarget(next) : m,
    ]);
    setState(() {});
    _reportPending();
  }

  // ---- 中身を入れる依頼 ----

  void _applyPrefill() {
    final p = widget.prefill;
    if (p == null) return;
    final attachments = p.attachments;
    if (attachments != null) {
      for (final d in List.of(_drafts.drafts)) {
        _drafts.remove(d.localId);
      }
      _drafts.restore(attachments);
    }
    final restored = <ComposerMention>[];
    final text = p.text.replaceAllMapped(chatMentionPattern, (m) {
      final id = m.group(1)!;
      final draft = _drafts.draftById(id);
      final ref = p.references.where((r) => r.attachmentId == id).firstOrNull;
      final existing = widget.mentionables.where((a) => a.id == id).firstOrNull;
      final title = draft != null
          ? chatDraftLabel(draft)
          : existing == null
          ? null
          : chatAttachmentTitle(AppLocalizations.of(context), existing);
      if (title == null) return '';
      final target = draft != null
          ? DraftMention(draft.localId)
          : ExistingMention(
              attachmentId: id,
              mode: ref?.mode ?? ChatAttachmentMode.mention,
            );
      final label = makeMentionLabel(title, [for (final r in restored) r.label]);
      restored.add(ComposerMention(label: label, target: target));
      return label;
    });
    _setMentions(restored);
    _setText(text);
    if (text.isNotEmpty) _focus.requestFocus();
    setState(() => _notice = null);
  }

  void _applyInsertRequest(ChatInsertRequest req) {
    final a = req.attachment;
    if (req.mode == ChatInsertMode.remove) {
      final m = _mentions
          .where(
            (x) =>
                x.target is ExistingMention &&
                (x.target as ExistingMention).attachmentId == a.id,
          )
          .firstOrNull;
      if (m != null) _removeMention(m);
      return;
    }
    _addMention(
      ExistingMention(
        attachmentId: a.id,
        mode: req.mode == ChatInsertMode.full
            ? ChatAttachmentMode.full
            : ChatAttachmentMode.mention,
      ),
      chatAttachmentTitle(AppLocalizations.of(context), a),
    );
  }

  // ---- 資料を足す ----

  Future<void> _pick(Future<List<PickedChatFile>> Function(ChatFilePicker) pick) async {
    final List<PickedChatFile> files;
    try {
      files = await pick(ref.read(chatFilePickerProvider));
    } on Object {
      if (mounted) {
        setState(() => _notice = const ComposerNoticeView.pickFailed());
      }
      return;
    }
    if (!mounted || files.isEmpty) return;
    await _addPicked(files);
  }

  Future<void> _addPicked(List<PickedChatFile> files) async {
    setState(() => _notice = null);
    final result = await _drafts.addFiles(files);
    if (!mounted) return;
    for (final d in result.added) {
      _addMention(
        DraftMention(d.localId),
        chatDraftLabel(d).isEmpty
            ? AppLocalizations.of(context).aiChatAttachmentUntitled
            : chatDraftLabel(d),
      );
    }
    setState(() {
      _notice = result.notice == null
          ? null
          : ComposerNoticeView.from(result.notice!);
    });
  }

  Future<void> _addLongText({
    String content = '',
    bool fromPaste = false,
    bool replacesInput = false,
  }) async {
    final value = await showChatTextDraftSheet(
      context,
      colors: widget.colors,
      initialContent: content,
      fromPaste: fromPaste,
    );
    if (value == null || !mounted) return;
    final draft = _drafts.addText(title: value.title, content: value.content);
    if (draft == null) {
      setState(() => _notice = ComposerNoticeView.limit(_drafts.maxPerMessage));
      return;
    }
    // 入力欄から回した本文は、資料にしたので入力欄からは消す
    if (replacesInput) _setText('');
    _addMention(
      DraftMention(draft.localId),
      chatDraftLabel(draft).isEmpty
          ? AppLocalizations.of(context).aiChatAttachmentUntitled
          : chatDraftLabel(draft),
    );
  }

  Future<void> _editTextDraft(ChatTextDraft draft) async {
    final value = await showChatTextDraftSheet(
      context,
      colors: widget.colors,
      initialTitle: draft.title,
      initialContent: draft.content,
      editing: true,
    );
    if (value == null || !mounted) return;
    _drafts.updateText(
      draft.localId,
      title: value.title,
      content: value.content,
    );
  }

  void _openDraft(ChatDraft draft) {
    if (draft is ChatTextDraft) {
      unawaited(_editTextDraft(draft));
      return;
    }
    unawaited(
      showChatDraftPreviewSheet(
        context,
        colors: widget.colors,
        drafts: _drafts,
        localId: draft.localId,
        onRemove: () => _removeDraft(draft.localId),
      ),
    );
  }

  // ---- 送る ----

  bool get _overLimit => _controller.text.length > chatMaxMessageChars;

  bool get _canSend =>
      !widget.disabled &&
      !_overLimit &&
      !_drafts.filesPending &&
      (_controller.text.trim().isNotEmpty || _drafts.drafts.isNotEmpty);

  void _submit() {
    if (!_canSend) return;
    final used = presentMentions(_controller.text, _mentions);
    final content = toMessageContent(_controller.text, used, (m) {
      final t = m.target;
      return switch (t) {
        ExistingMention() => t.attachmentId,
        DraftMention() => _drafts.tokenIdFor(t),
      };
    }).trim();
    final attachments = _drafts.toNewAttachments();
    final references = existingReferences(used);
    _setMentions(const []);
    _setText('');
    _drafts.clearAfterSend();
    setState(() {
      _notice = null;
      _picker = null;
      _activeLabel = null;
    });
    widget.onSend(content, attachments, references);
  }

  // ---- 「@」の候補 ----

  List<ChatAttachment> get _pickerItems {
    final picker = _picker;
    if (picker == null) return const [];
    final q = picker.query.toLowerCase();
    final matches = [
      for (final a in widget.mentionables)
        if (q.isEmpty ||
            '${a.title ?? ''} ${a.fileName ?? ''}'.toLowerCase().contains(q))
          a,
    ];
    final recent = matches.length > 8 ? matches.sublist(matches.length - 8) : matches;
    return recent.reversed.toList();
  }

  void _choosePicked(ChatAttachment a, ChatAttachmentMode mode) {
    final picker = _picker;
    if (picker == null) return;
    final range = TextRange(start: picker.start, end: _caret);
    setState(() => _picker = null);
    _addMention(
      ExistingMention(attachmentId: a.id, mode: mode),
      chatAttachmentTitle(AppLocalizations.of(context), a),
      range: range,
    );
  }

  // ---- 表示 ----

  String _noticeText(AppLocalizations l, ComposerNoticeView n) => switch (n) {
    ComposerNoticeView(pickFailed: true) => l.aiChatAttachPickFailed,
    ComposerNoticeView(limit: final max?) =>
      l.aiChatAttachmentLimitPerMessage('$max'),
    ComposerNoticeView(:final code, :final detail) => chatFileErrorCopy(
      l,
      code,
      detail,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.colors;
    final generating = widget.onStop != null;
    final locale = Localizations.localeOf(context).toString();
    String fmt(num n) => NumberFormat.decimalPattern(locale).format(n);
    final drafts = _drafts.drafts;
    final length = _controller.text.length;
    final showCounter = length > chatMaxMessageChars - 500;
    final active = _activeLabel == null
        ? null
        : _mentions.where((m) => m.label == _activeLabel).firstOrNull;
    final pinnedTokens = widget.selectedAttachments.fold<int>(
      0,
      (sum, a) => sum + a.tokenCount,
    );
    final pinnedCredits = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    ).format(pinnedTokens / 10000 * chatCreditsPer10kTokens);
    final hasChips =
        drafts.isNotEmpty || widget.selectedAttachments.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editingLabel != null)
          _Bar(
            colors: c,
            icon: Icons.edit_outlined,
            text: widget.editingLabel!,
            tooltip: l10n.aiChatEditCancel,
            onClose: widget.onCancelEdit,
            tint: c.accent,
          ),
        if (widget.selectedAttachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              l10n.aiChatPinnedSummary(
                '${widget.selectedAttachments.length}',
                pinnedCredits,
                '${(pinnedTokens / chatMaxSelectedTokens * 100).round()}',
              ),
              style: TextStyle(color: c.stageText, fontSize: 11.5),
            ),
          ),
        if (hasChips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in widget.selectedAttachments)
                  ChatPinnedChip(
                    attachment: a,
                    colors: c,
                    onUnpin: () => widget.onUnselectAttachment?.call(a.id),
                  ),
                for (final d in drafts)
                  ChatDraftChip(
                    key: ValueKey(d.localId),
                    draft: d,
                    colors: c,
                    onOpen: () => _openDraft(d),
                    onRemove: () => _removeDraft(d.localId),
                  ),
              ],
            ),
          ),
        if (widget.selectedText != null)
          _Bar(
            colors: c,
            icon: Icons.format_quote_rounded,
            text: widget.selectedText!,
            maxLines: 2,
            tooltip: l10n.aiChatDismiss,
            onClose: widget.onClearSelectedText,
            tint: c.quoteBorder,
          ),
        if (widget.lectureTitle != null)
          _Bar(
            colors: c,
            icon: Icons.menu_book_outlined,
            text: l10n.aiChatAttachedLecture(widget.lectureTitle!),
            tooltip: l10n.aiChatDismiss,
            onClose: widget.onDetachLecture,
            tint: c.accent,
          ),
        if (_notice != null)
          _Bar(
            colors: c,
            icon: Icons.error_outline_rounded,
            text: _noticeText(l10n, _notice!),
            maxLines: 3,
            tooltip: l10n.aiChatDismiss,
            onClose: () => setState(() => _notice = null),
            tint: c.danger,
          ),
        if (_picker == null && active != null) _actionBarFor(active),
        if (_picker != null)
          ChatMentionPicker(
            colors: c,
            items: _pickerItems,
            onPick: _choosePicked,
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          decoration: BoxDecoration(
            color: c.inputBackground,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _overLimit ? c.danger : c.inputBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: _attachMenu(l10n),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  inputFormatters: [
                    _ComposerFormatter(
                      mentions: () => _mentions,
                      canDivert: () => !_drafts.isFull,
                      onLongPaste: (pasted) {
                        if (mounted) {
                          unawaited(
                            _addLongText(content: pasted, fromPaste: true),
                          );
                        }
                      },
                    ),
                  ],
                  style: TextStyle(color: c.text, fontSize: 15, height: 1.5),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(color: c.hintText),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: generating
                    ? _RoundButton(
                        icon: Icons.stop_rounded,
                        color: c.accent,
                        tooltip: widget.stopping
                            ? l10n.aiChatStopping
                            : l10n.aiChatStop,
                        onTap: widget.stopping ? null : widget.onStop,
                      )
                    : _RoundButton(
                        icon: Icons.arrow_upward_rounded,
                        color: c.accent,
                        tooltip: _drafts.filesPending
                            ? l10n.aiChatFileNotReadyHint
                            : l10n.aiChatSend,
                        onTap: _canSend ? _submit : null,
                      ),
              ),
            ],
          ),
        ),
        if (showCounter)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: _overLimit
                  ? Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          l10n.aiChatErrorTooLong(fmt(chatMaxMessageChars)),
                          style: TextStyle(color: c.danger, fontSize: 12),
                        ),
                        if (!_drafts.isFull)
                          TextButton.icon(
                            onPressed: () => unawaited(
                              _addLongText(
                                content: _controller.text,
                                fromPaste: true,
                                replacesInput: true,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: c.accent,
                            ),
                            icon: const Icon(Icons.attach_file_rounded, size: 14),
                            label: Text(
                              l10n.aiChatAttachmentConvert,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    )
                  : Text(
                      '${fmt(length)} / ${fmt(chatMaxMessageChars)}',
                      style: TextStyle(color: c.stageText, fontSize: 12),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _actionBarFor(ComposerMention mention) {
    final l = AppLocalizations.of(context);
    final target = mention.target;
    ChatAttachment? attachment;
    ChatDraft? draft;
    if (target is ExistingMention) {
      attachment = widget.mentionables
          .where((a) => a.id == target.attachmentId)
          .firstOrNull;
    } else if (target is DraftMention) {
      draft = _drafts.draftById(target.localId);
    }
    final title = attachment != null
        ? chatAttachmentTitle(l, attachment)
        : draft != null
        ? chatDraftLabel(draft)
        : mention.label.substring(1);
    final kind = attachment?.kind ??
        (draft is ChatFileDraft ? draft.fileKind.name : 'text');
    final preview = draft is ChatFileDraft ? draft.previewBytes : null;
    return ChatMentionActionBar(
      colors: widget.colors,
      mention: mention,
      title: title,
      kind: kind,
      thumb: preview == null ? null : MemoryImage(preview),
      onView: () {
        if (target is ExistingMention) {
          widget.onViewAttachment?.call(target.attachmentId);
        } else if (draft != null) {
          _openDraft(draft);
        }
      },
      onToggleMode: () => _toggleMentionMode(mention),
      onRemove: () => _removeMention(mention),
    );
  }

  Widget _attachMenu(AppLocalizations l) {
    final c = widget.colors;
    final full = _drafts.isFull;
    final itemStyle = TextStyle(color: c.actionForegroundStrong, fontSize: 14);
    final hintStyle = TextStyle(color: c.stageText, fontSize: 11.5);
    final limitHint = l.aiChatAttachmentLimitPerMessage(
      '${_drafts.maxPerMessage}',
    );
    PopupMenuItem<_AttachChoice> item(
      _AttachChoice value,
      IconData icon,
      String label,
      String hint, {
      bool enabled = true,
    }) => PopupMenuItem<_AttachChoice>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? c.accent : c.actionForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: itemStyle.copyWith(
                    color: enabled ? c.actionForegroundStrong : c.stageText,
                  ),
                ),
                Text(hint, style: hintStyle),
              ],
            ),
          ),
        ],
      ),
    );
    return PopupMenuButton<_AttachChoice>(
      key: _menuKey,
      tooltip: l.aiChatAttach,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.add_rounded, size: 24, color: c.actionForeground),
      color: c.menuBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.menuBorder),
      ),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      onSelected: (choice) {
        switch (choice) {
          case _AttachChoice.materials:
            widget.onOpenAttachmentList?.call();
          case _AttachChoice.longText:
            unawaited(_addLongText());
          case _AttachChoice.camera:
            unawaited(_pick((p) => p.takePhoto()));
          case _AttachChoice.photo:
            unawaited(_pick((p) => p.pickPhotos()));
          case _AttachChoice.file:
            unawaited(_pick((p) => p.pickFiles()));
        }
      },
      itemBuilder: (_) => [
        item(
          _AttachChoice.materials,
          Icons.folder_copy_outlined,
          l.aiChatAttachSelect,
          widget.mentionables.isEmpty
              ? l.aiChatAttachSelectNone
              : l.aiChatAttachSelectHint,
          enabled:
              widget.mentionables.isNotEmpty &&
              widget.onOpenAttachmentList != null,
        ),
        item(
          _AttachChoice.longText,
          Icons.notes_rounded,
          l.aiChatAttachLongText,
          full ? limitHint : l.aiChatAttachTextHint,
          enabled: !full,
        ),
        item(
          _AttachChoice.camera,
          Icons.photo_camera_outlined,
          l.aiChatAttachCamera,
          full ? limitHint : l.aiChatAttachCameraHint,
          enabled: !full,
        ),
        item(
          _AttachChoice.photo,
          Icons.photo_library_outlined,
          l.aiChatAttachPhoto,
          full ? limitHint : l.aiChatAttachPhotoHint,
          enabled: !full,
        ),
        item(
          _AttachChoice.file,
          Icons.upload_file_rounded,
          l.aiChatAttachFile,
          full ? limitHint : l.aiChatAttachFileHint,
          enabled: !full,
        ),
      ],
    );
  }
}

enum _AttachChoice { materials, longText, camera, photo, file }

/// 入力欄の上に出す案内の中身(ファイルのエラー・上限・選べなかった)。
class ComposerNoticeView {
  const ComposerNoticeView._({
    this.code,
    this.detail = const {},
    this.limit,
    this.pickFailed = false,
  });

  const ComposerNoticeView.pickFailed() : this._(pickFailed: true);
  const ComposerNoticeView.limit(int max) : this._(limit: max);

  factory ComposerNoticeView.from(ChatComposerNotice notice) =>
      switch (notice) {
        ChatNoticeLimit() => ComposerNoticeView.limit(notice.max),
        ChatNoticeFileError() => ComposerNoticeView._(
          code: notice.code,
          detail: notice.detail,
        ),
      };

  final String? code;
  final Map<String, dynamic> detail;
  final int? limit;
  final bool pickFailed;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: enabled ? .9 : .28),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white.withValues(alpha: enabled ? 1 : .7),
          ),
        ),
      ),
    );
  }
}

/// 入力欄の上に出す細い帯(編集中・選択した文章・話題の講義・案内)。
class _Bar extends StatelessWidget {
  const _Bar({
    required this.colors,
    required this.icon,
    required this.text,
    required this.tint,
    required this.tooltip,
    this.maxLines = 1,
    this.onClose,
  });

  final ChatColors colors;
  final IconData icon;
  final String text;
  final Color tint;
  final String tooltip;
  final int maxLines;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text, fontSize: 12.5, height: 1.4),
            ),
          ),
          if (onClose != null)
            InkResponse(
              onTap: onClose,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colors.actionForeground,
                  semanticLabel: tooltip,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
