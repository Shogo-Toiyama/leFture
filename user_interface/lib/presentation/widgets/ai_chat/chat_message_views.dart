// lib/presentation/widgets/ai_chat/chat_message_views.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/core/utils/chat_markdown_text.dart';
import 'package:lefture/core/utils/chat_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_markdown.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_message_actions.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_thinking_indicator.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/selection_floating_menu.dart';

/// 編集中の表示: target=直しているメッセージ(枠をつける) / doomed=送ると消えるメッセージ(薄くする)。
enum ChatEditState { target, doomed }

/// 自分のメッセージは、表示でこの行数を超えたら、先頭の[_collapsedLines]行だけ見せて「もっと見る」で全文にする。
const _collapseOverLines = 10;
const _collapsedLines = 6;

// ===========================================================================
// 自分のメッセージ(吹き出し)
// ===========================================================================

/// 自分のメッセージ。吹き出し(長ければ畳む)、選択して「Ask」した引用、資料のチップ、
/// コピー・編集、送れなかったときの表示。
class ChatUserMessage extends StatelessWidget {
  const ChatUserMessage({
    super.key,
    required this.message,
    required this.colors,
    this.attachments = const [],
    this.attachmentsById = const {},
    this.onOpenAttachment,
    this.onEdit,
    this.editState,
  });

  final LocalChatMessage message;
  final ChatColors colors;

  /// このメッセージで添付した資料(サーバーの一覧から)。
  final List<ChatAttachment> attachments;

  /// この会話の資料(外したものも含む)。本文の中のチップの名前に使う。
  final Map<String, ChatAttachment> attachmentsById;
  final void Function(ChatAttachment attachment)? onOpenAttachment;

  /// 編集する(下の入力欄で直す)。生成中・送れていないメッセージでは渡さない。
  final VoidCallback? onEdit;
  final ChatEditState? editState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = message.message.content;
    final selected = message.message.context.selectedText;
    final inlineIds = messageMentionIds(content).toSet();
    // 本文の中で指している資料は、その位置のチップで見せるので、上には出さない
    final chips = [
      for (final a in attachments)
        if (!inlineIds.contains(a.id)) a,
    ];
    final failed = message.failedCode != null;

    String titleOf(String id) {
      final a = attachmentsById[id];
      return (a?.title?.isNotEmpty == true ? a!.title! : a?.fileName) ??
          l10n.aiChatMentionRemoved;
    }

    // コピーする本文: 資料の印は資料の名前に直す
    final copyText = [
      for (final p in splitMessageText(content))
        switch (p) {
          ChatTextPart() => p.text,
          ChatMentionPart() => titleOf(p.attachmentId),
        },
    ].join();

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in chips)
                  _AttachmentChip(
                    title: a.title?.isNotEmpty == true
                        ? a.title!
                        : (a.fileName ?? l10n.aiChatAttachmentUntitled),
                    colors: colors,
                    status: a.status,
                    onTap: onOpenAttachment == null
                        ? null
                        : () => onOpenAttachment!(a),
                  ),
              ],
            ),
          ),
        if (content.isNotEmpty || selected != null)
          _Bubble(
            colors: colors,
            outlined: editState == ChatEditState.target,
            faded: failed,
            quote: selected,
            content: content,
            mentionTitle: titleOf,
            mentionChip: (id) {
              final a = attachmentsById[id];
              return _InlineMention(
                title: titleOf(id),
                removed: a == null,
                full: message.message.context.attachments.any(
                  (r) =>
                      r.attachmentId == id && r.mode == ChatAttachmentMode.full,
                ),
                colors: colors,
                onTap: a == null || onOpenAttachment == null
                    ? null
                    : () => onOpenAttachment!(a),
              );
            },
          ),
        if (content.isNotEmpty)
          ChatMessageActions(
            copyText: copyText,
            colors: colors,
            onEdit: onEdit,
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 13,
                  color: colors.danger,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.aiChatNotSent,
                  style: TextStyle(color: colors.danger, fontSize: 12.5),
                ),
              ],
            ),
          ),
      ],
    );
    if (editState == ChatEditState.doomed) {
      body = Opacity(opacity: .38, child: body);
    }
    return Align(alignment: Alignment.centerRight, child: body);
  }
}

/// 自分の吹き出し。形は `border-radius: 16px 16px 4px 16px`、幅は画面の85%まで。
class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.colors,
    required this.content,
    required this.mentionTitle,
    required this.mentionChip,
    this.quote,
    this.outlined = false,
    this.faded = false,
  });

  final ChatColors colors;
  final String content;
  final String? quote;
  final bool outlined;
  final bool faded;
  final String Function(String id) mentionTitle;
  final Widget Function(String id) mentionChip;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  bool _expanded = false;

  static const _fontSize = 15.0;
  static const _height = 1.6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.colors;
    final textStyle = TextStyle(
      color: c.bubbleText,
      fontSize: _fontSize,
      height: _height,
    );
    final maxWidth = MediaQuery.sizeOf(context).width * .85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Opacity(
        opacity: widget.faded ? .65 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.bubbleBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(color: c.bubbleBorder),
          ),
          position: DecorationPosition.background,
          child: Container(
            foregroundDecoration: widget.outlined
                ? BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                    border: Border.all(color: c.accent, width: 2),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.quote != null)
                  _Quote(text: widget.quote!, colors: c),
                if (widget.content.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final spans = _spans(textStyle);
                      final plain = _plainText();
                      final overflowing =
                          _lineCount(plain, textStyle, constraints.maxWidth) >
                          _collapseOverLines;
                      final collapsed = overflowing && !_expanded;
                      final text = Text.rich(
                        TextSpan(children: spans),
                        style: textStyle,
                        maxLines: collapsed ? _collapsedLines : null,
                        overflow: collapsed
                            ? TextOverflow.clip
                            : TextOverflow.visible,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (collapsed)
                            ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black,
                                  Colors.black,
                                  Colors.transparent,
                                ],
                                stops: [0, .65, 1],
                              ).createShader(rect),
                              child: text,
                            )
                          else
                            text,
                          if (overflowing)
                            InkWell(
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _expanded
                                          ? l10n.aiChatShowLess
                                          : l10n.aiChatShowMore,
                                      style: TextStyle(
                                        color: c.accent,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    AnimatedRotation(
                                      turns: _expanded ? .5 : 0,
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 16,
                                        color: c.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 本文を、文字と資料のチップに分けて並べる。
  List<InlineSpan> _spans(TextStyle style) => [
    for (final p in splitMessageText(widget.content))
      switch (p) {
        ChatTextPart() => TextSpan(text: p.text),
        ChatMentionPart() => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: widget.mentionChip(p.attachmentId),
        ),
      },
  ];

  /// 行数を数えるための平文(チップは名前の文字に置き換える)。
  String _plainText() => [
    for (final p in splitMessageText(widget.content))
      switch (p) {
        ChatTextPart() => p.text,
        ChatMentionPart() => widget.mentionTitle(p.attachmentId),
      },
  ].join();

  /// 折り返しを含む表示の行数(幅が変わるたびに数え直す)。
  int _lineCount(String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines;
  }
}

/// 選択して「Ask」した文章の引用(最大4行)。
class _Quote extends StatelessWidget {
  const _Quote({required this.text, required this.colors});

  final String text;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.quoteBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: colors.quoteBorder, width: 2)),
      ),
      child: Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.quoteText, fontSize: 13.5, height: 1.5),
      ),
    );
  }
}

/// 吹き出しの上に並べる資料のチップ。
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.title,
    required this.colors,
    required this.status,
    this.onTap,
  });

  final String title;
  final ChatColors colors;
  final ChatAttachmentStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = status == ChatAttachmentStatus.ready;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.bubbleBorder),
          color: colors.quoteBackground,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 14,
              color: ready ? colors.accent : colors.danger,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.bubbleText, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本文の中で資料を指す印(吹き出しの中のチップ)。
class _InlineMention extends StatelessWidget {
  const _InlineMention({
    required this.title,
    required this.removed,
    required this.full,
    required this.colors,
    this.onTap,
  });

  final String title;
  final bool removed;
  final bool full;
  final ChatColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = removed
        ? colors.actionForeground
        : (full ? colors.accent : colors.care);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 13.5,
            decoration: removed ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// AIの回答
// ===========================================================================

/// AIの回答。生成中は星雲と段階の文言、完了後はMarkdown(数式・出典の印)、出典のチップ、操作の行。
/// 回答の一部を長押しで選ぶと、標準のメニューに「返信」(webappの「Ask」)が出る。
class ChatAssistantMessage extends StatelessWidget {
  const ChatAssistantMessage({
    super.key,
    required this.message,
    required this.world,
    required this.colors,
    this.attachmentsById = const {},
    this.question,
    this.onResend,
    this.onRegenerate,
    this.onReplyToSelection,
    this.onCitationTap,
    this.onOpenLink,
    this.editState,
  });

  final LocalChatMessage message;
  final ChatWorld world;
  final ChatColors colors;
  final Map<String, ChatAttachment> attachmentsById;

  /// この回答のもとになった質問の本文(問題の報告に添える)。
  final String? question;

  /// 返答に失敗したとき、直前の質問をもう一度送る。
  final VoidCallback? onResend;

  /// 作り直す(最後の回答だけ)。
  final VoidCallback? onRegenerate;

  /// 回答の一部を選んで「返信」したとき(次の送信に添える引用にする)。
  final void Function(ChatSelection selection)? onReplyToSelection;

  /// 出典を押したとき。specsは押された引用の区切り。
  final void Function(ChatCitation citation, List<String> specs)? onCitationTap;
  final void Function(String url)? onOpenLink;
  final ChatEditState? editState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final m = message.message;
    final c = colors;

    // 生成中は出典の候補(pendingSources)、完了後は本文で実際に使われた出典(citations)で番号を引く。
    // 番号は講義・チャットが "1", "2"…、Webのページが "W1", "W2"…。
    final byRef = <String, ChatCitation>{
      for (final x in message.pendingSources ?? const <ChatCitation>[])
        x.ref: x,
      for (final x in m.citations) x.ref: x,
    };

    Widget wrap(Widget child) {
      if (editState == ChatEditState.doomed) {
        return Opacity(opacity: .38, child: child);
      }
      return child;
    }

    // 危機対応の定型文: 共感の文と相談窓口(LLMに生成させない)
    if (m.status == ChatMessageStatus.crisis) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.care.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.care.withValues(alpha: .35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                Icons.volunteer_activism_outlined,
                size: 18,
                color: c.care,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChatMarkdown(
                markdown: m.content,
                colors: c,
                onOpenLink: onOpenLink,
              ),
            ),
          ],
        ),
      );
    }

    // 返答の前に止めた: 大きな空の枠は出さず、質問の下に小さく一行だけ
    if (m.status == ChatMessageStatus.stopped && m.content.trim().isEmpty) {
      return wrap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.aiChatStopped,
                  style: TextStyle(color: c.stageText, fontSize: 12.5),
                ),
                if (onRegenerate != null) ...[
                  const SizedBox(width: 10),
                  _LinkButton(
                    label: l10n.aiChatActionRegenerate,
                    icon: Icons.refresh_rounded,
                    colors: c,
                    onTap: onRegenerate!,
                  ),
                ],
              ],
            ),
            _StoppedAttachmentsNotice(
              message: message,
              attachmentsById: attachmentsById,
              colors: c,
            ),
          ],
        ),
      );
    }

    final isGenerating = m.status == ChatMessageStatus.streaming;
    final hasFinalText =
        m.status == ChatMessageStatus.complete ||
        m.status == ChatMessageStatus.stopped;
    final showStage =
        isGenerating &&
        m.content.isEmpty &&
        !message.reconnecting &&
        !message.stopping;

    final copyText = stripCitationMarkers(m.content, byRef.keys.toSet()).trim();

    Widget markdown = ChatMarkdown(
      markdown: m.content,
      colors: c,
      citationsByRef: byRef,
      onCitationTap: onCitationTap,
      onOpenLink: onOpenLink,
    );
    if (hasFinalText && onReplyToSelection != null) {
      markdown = _ReplySelectionArea(
        world: world,
        onReply: (text) => onReplyToSelection!(
          ChatSelection(text: text, replyToMessageId: m.id),
        ),
        child: markdown,
      );
    }

    return wrap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showStage)
            ChatThinkingIndicator(
              label: chatStageLabel(l10n, message),
              world: world,
              colors: c,
              startedAt: m.createdAt,
            ),
          if (m.content.isNotEmpty) markdown,
          if (isGenerating &&
              m.content.isNotEmpty &&
              message.stage == ChatStage.indexingAttachments)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _SmallStage(
                label: l10n.aiChatStageIndexingAttachments,
                world: world,
                colors: c,
              ),
            ),
          _AttachmentNotice(
            message: message,
            attachmentsById: attachmentsById,
            colors: c,
          ),
          if (message.reconnecting)
            _SmallStage(
              label: l10n.aiChatReconnecting,
              world: world,
              colors: c,
            ),
          if (m.status == ChatMessageStatus.error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.aiChatReplyFailed,
                    style: TextStyle(color: c.danger, fontSize: 13.5),
                  ),
                  if (onResend != null)
                    _LinkButton(
                      label: l10n.aiChatActionRegenerate,
                      icon: Icons.refresh_rounded,
                      colors: c,
                      onTap: onResend!,
                    ),
                ],
              ),
            ),
          if (message.stopping)
            _SmallStage(label: l10n.aiChatStopping, world: world, colors: c),
          if (message.stopFailed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.aiChatStopFailed,
                style: TextStyle(color: c.danger, fontSize: 13.5),
              ),
            ),
          if (m.status == ChatMessageStatus.stopped)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.aiChatStopped,
                style: TextStyle(color: c.stageText, fontSize: 12.5),
              ),
            ),
          _StoppedAttachmentsNotice(
            message: message,
            attachmentsById: attachmentsById,
            colors: c,
          ),
          if (hasFinalText && m.citations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                label: l10n.aiChatSourcesLabel,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final citation in m.citations)
                      _SourceChip(
                        citation: citation,
                        colors: c,
                        onTap:
                            canOpenChatCitation(citation) &&
                                onCitationTap != null
                            // チップはその出典の引用された区切りを全部見せる
                            ? () => onCitationTap!(
                                citation,
                                citation.passages.keys.toList(),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          if (hasFinalText)
            ChatMessageActions(
              copyText: copyText,
              colors: c,
              detailsFor: message,
              question: question,
              onRegenerate: onRegenerate,
            ),
        ],
      ),
    );
  }
}

/// 回答の一部を選べるようにする。選ぶと、Deep Notes・復習カードと同じ浮かぶメニューに
/// 「AIに聞く」(選んだ文章を引用して入力欄へ)と「コピー」が出る(webappの SelectionAskArea)。
/// 選んだ文字から、出典の印・数式の場所を表す文字(U+FFFC)を取り除いて渡す。
class _ReplySelectionArea extends StatefulWidget {
  const _ReplySelectionArea({
    required this.world,
    required this.onReply,
    required this.child,
  });

  final ChatWorld world;
  final void Function(String text) onReply;
  final Widget child;

  @override
  State<_ReplySelectionArea> createState() => _ReplySelectionAreaState();
}

class _ReplySelectionAreaState extends State<_ReplySelectionArea> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SelectionArea(
      onSelectionChanged: (content) {
        _selected = (content?.plainText ?? '').replaceAll('\uFFFC', '').trim();
      },
      contextMenuBuilder: (context, state) {
        if (_selected.isEmpty) return const SizedBox.shrink();
        return buildSelectionFloatingMenu(
          state: state,
          world: widget.world,
          actions: [
            SelectionMenuAction(
              label: l10n.cardSelectionToolbarAskLabel,
              emphasized: true,
              onTap: () {
                final text = _selected;
                state.clearSelection();
                widget.onReply(text);
              },
            ),
            SelectionMenuAction(
              label: l10n.cardSelectionToolbarCopyLabel,
              onTap: () {
                final text = _selected;
                state.clearSelection();
                unawaited(Clipboard.setData(ClipboardData(text: text)));
              },
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// 小さな段階表示(再接続中・停止中)。星雲は出さず、小さな星雲1つと文言だけ。
class _SmallStage extends StatelessWidget {
  const _SmallStage({
    required this.label,
    required this.world,
    required this.colors,
  });

  final String label;
  final ChatWorld world;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ChatThinkingIndicator(
        label: label,
        world: world,
        colors: colors,
        startedAt: DateTime.now(),
        nebulaSize: 24,
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final ChatColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 回答の下の出典チップ(番号 + 種類 + 短い名前)。
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.citation, required this.colors, this.onTap});

  final ChatCitation citation;
  final ChatColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = chatSourceKindLabel(l10n, citation.sourceType);
    return Material(
      color: colors.quoteBackground,
      shape: StadiumBorder(side: BorderSide(color: colors.preBorder)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 48,
          ),
          padding: const EdgeInsets.fromLTRB(5, 4, 11, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.citeBackground,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  citation.ref,
                  style: TextStyle(
                    color: colors.citeText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (kind.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  kind,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  chatCitationShortLabel(citation),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.text, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 全文で読む枠を超えて外した資料・長すぎて全文にできなかった資料の知らせ(返答の下)。
class _AttachmentNotice extends StatelessWidget {
  const _AttachmentNotice({
    required this.message,
    required this.attachmentsById,
    required this.colors,
  });

  final LocalChatMessage message;
  final Map<String, ChatAttachment> attachmentsById;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    final notice = message.message.context.attachmentNotice;
    if (notice == null || notice.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    String names(List<String> ids) => [
      for (final id in ids)
        '「${attachmentsById[id]?.title ?? attachmentsById[id]?.fileName ?? l10n.aiChatAttachmentUntitled}」',
    ].join();
    return _NoticeBox(
      colors: colors,
      lines: [
        if (notice.unpinned.isNotEmpty)
          l10n.aiChatNoticeUnpinned(
            names(notice.unpinned),
            '$chatMaxSelectedTokens',
          ),
        if (notice.tooLong.isNotEmpty)
          l10n.aiChatNoticeTooLong(names(notice.tooLong)),
      ],
    );
  }
}

/// 資料の読み込みの途中で止めたため、使えなくなった資料の知らせ(もう一度添付してもらう)。
class _StoppedAttachmentsNotice extends StatelessWidget {
  const _StoppedAttachmentsNotice({
    required this.message,
    required this.attachmentsById,
    required this.colors,
  });

  final LocalChatMessage message;
  final Map<String, ChatAttachment> attachmentsById;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    final ids = message.message.context.stoppedAttachments;
    if (ids.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final titles = [
      for (final id in ids)
        '「${attachmentsById[id]?.title ?? attachmentsById[id]?.fileName ?? l10n.aiChatAttachmentUntitled}」',
    ].join();
    return _NoticeBox(
      colors: colors,
      lines: [l10n.aiChatStoppedAttachments(titles)],
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.colors, required this.lines});

  final ChatColors colors;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.noticeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.noticeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                color: colors.noticeText,
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}
