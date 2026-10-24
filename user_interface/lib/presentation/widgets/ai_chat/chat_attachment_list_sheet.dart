// lib/presentation/widgets/ai_chat/chat_attachment_list_sheet.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_attachment_files.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_attachment_viewer.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';

/// この会話の資料の一覧(入力欄の「＋」の「この会話の資料」から開く)。
///
/// 行を押すと「全文で添付」「メンション」「中身を見る」を選べる(webappと同じ。2026-10-07にユーザーと合意):
/// - 全文で添付: 入力欄に「@名前」を入れ、送るとAIが毎回全文を読む(外すまで続く)
/// - メンション: 入力欄に「@名前」を入れ、そのメッセージでこの資料を指していることをAIに伝える
/// 何もしていない資料も、名前と要約はAIが知っていて、必要なら目次と検索で読む。
/// 一覧は開いたまま(続けていくつも選べるように)。入力欄には裏で「@名前」が入る。
Future<void> showChatAttachmentListSheet(
  BuildContext context, {
  required ChatColors colors,
  required ValueListenable<List<ChatAttachmentRef>> pendingRefs,
  required void Function(ChatAttachment attachment, ChatInsertMode mode)
  onAttach,
  required void Function(ChatAttachment attachment) onView,
  required Future<void> Function(ChatAttachment attachment) onPin,
  required Future<void> Function(ChatAttachment attachment) onUnpin,
}) {
  return showChatSheet<void>(
    context,
    colors,
    (_) => _AttachmentList(
      colors: colors,
      pendingRefs: pendingRefs,
      onAttach: onAttach,
      onView: onView,
      onPin: onPin,
      onUnpin: onUnpin,
    ),
  );
}

class _AttachmentList extends ConsumerStatefulWidget {
  const _AttachmentList({
    required this.colors,
    required this.pendingRefs,
    required this.onAttach,
    required this.onView,
    required this.onPin,
    required this.onUnpin,
  });

  final ChatColors colors;
  final ValueListenable<List<ChatAttachmentRef>> pendingRefs;
  final void Function(ChatAttachment attachment, ChatInsertMode mode) onAttach;
  final void Function(ChatAttachment attachment) onView;
  final Future<void> Function(ChatAttachment attachment) onPin;
  final Future<void> Function(ChatAttachment attachment) onUnpin;

  @override
  ConsumerState<_AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends ConsumerState<_AttachmentList> {
  String? _expandedId;
  String? _busyId;
  String? _failedId;

  Future<void> _pin(ChatAttachment a) async {
    setState(() {
      _failedId = null;
      _busyId = a.id;
    });
    try {
      await widget.onPin(a);
    } catch (_) {
      if (mounted) setState(() => _failedId = a.id);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _unpin(ChatAttachment a) async {
    setState(() {
      _failedId = null;
      _busyId = a.id;
    });
    try {
      await widget.onUnpin(a);
    } catch (_) {
      if (mounted) setState(() => _failedId = a.id);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final locale = Localizations.localeOf(context).toString();
    final compact = NumberFormat.compact(locale: locale)
      ..maximumFractionDigits = 1;
    String tokens(int n) => compact.format(n);
    final all = ref.watch(
      chatConversationProvider.select((s) => s.attachments),
    );
    // 使えるものと確認中のもの。断った・失敗した資料は、メッセージの上のチップにだけ出す
    final attachments = [
      for (final a in all)
        if (a.status == ChatAttachmentStatus.ready ||
            a.status == ChatAttachmentStatus.processing)
          a,
    ];
    // 新しく添付したものを上に(一緒に読んでいるのはたいてい最後に貼った資料)
    final ordered = attachments.reversed.toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatSheetHeader(
            colors: c,
            icon: Icons.attach_file_rounded,
            badge: l.aiChatSourceAttachment,
            badgeMeta: '${attachments.length} / $chatMaxAttachmentsPerThread',
            title: l.aiChatAttachmentsTitle,
          ),
          Expanded(
            child: ValueListenableBuilder<List<ChatAttachmentRef>>(
              valueListenable: widget.pendingRefs,
              builder: (context, pendingRefs, _) {
                if (ordered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.aiChatAttachmentsEmpty,
                      style: TextStyle(
                        color: c.stageText,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),
                  );
                }
                final pendingMode = {
                  for (final r in pendingRefs) r.attachmentId: r.mode,
                };
                // 送ったときに全文で読む資料: 今全文で読んでいる資料 + 入力欄で「全文で添付」にした資料
                final pinnedTokens = attachments
                    .where(
                      (a) =>
                          a.selected ||
                          pendingMode[a.id] == ChatAttachmentMode.full,
                    )
                    .fold<int>(0, (sum, a) => sum + a.tokenCount);
                final hasPendingFull = attachments.any(
                  (a) =>
                      !a.selected &&
                      pendingMode[a.id] == ChatAttachmentMode.full,
                );
                final over = pinnedTokens > chatMaxSelectedTokens;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    _Budget(
                      colors: c,
                      text: hasPendingFull
                          ? l.aiChatAttachmentSelectedPending(
                              tokens(pinnedTokens),
                              tokens(chatMaxSelectedTokens),
                            )
                          : l.aiChatAttachmentSelectedTotal(
                              tokens(pinnedTokens),
                              tokens(chatMaxSelectedTokens),
                            ),
                      ratio: pinnedTokens / chatMaxSelectedTokens,
                      over: over,
                      overNote: over ? l.aiChatAttachmentOverLimitNote : null,
                      hint: l.aiChatAttachmentListHint,
                    ),
                    for (final a in ordered)
                      _Row(
                        colors: c,
                        attachment: a,
                        pending: pendingMode[a.id],
                        expanded: _expandedId == a.id,
                        busy: _busyId == a.id,
                        failed: _failedId == a.id,
                        tokens: tokens,
                        onToggle: () => setState(
                          () => _expandedId = _expandedId == a.id ? null : a.id,
                        ),
                        onAttach: (mode) => widget.onAttach(a, mode),
                        onView: () => widget.onView(a),
                        onPin: () => unawaited(_pin(a)),
                        onUnpin: () => unawaited(_unpin(a)),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Budget extends StatelessWidget {
  const _Budget({
    required this.colors,
    required this.text,
    required this.ratio,
    required this.over,
    required this.hint,
    this.overNote,
  });

  final ChatColors colors;
  final String text;
  final double ratio;
  final bool over;
  final String hint;
  final String? overNote;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: c.text, fontSize: 12.5)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 5,
              backgroundColor: c.rule,
              color: over ? c.danger : c.accent,
            ),
          ),
          if (overNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                overNote!,
                style: TextStyle(color: c.danger, fontSize: 12, height: 1.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              hint,
              style: TextStyle(color: c.stageText, fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.colors,
    required this.attachment,
    required this.pending,
    required this.expanded,
    required this.busy,
    required this.failed,
    required this.tokens,
    required this.onToggle,
    required this.onAttach,
    required this.onView,
    required this.onPin,
    required this.onUnpin,
  });

  final ChatColors colors;
  final ChatAttachment attachment;
  final ChatAttachmentMode? pending;
  final bool expanded;
  final bool busy;
  final bool failed;
  final String Function(int) tokens;
  final VoidCallback onToggle;
  final void Function(ChatInsertMode mode) onAttach;
  final VoidCallback onView;
  final VoidCallback onPin;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final a = attachment;
    final locale = Localizations.localeOf(context).toString();
    final meta = <String>[
      if (a.fileKind == ChatFileKind.image)
        l.aiChatFileImage
      else if (a.fileKind == ChatFileKind.pdf && a.pageCount != null)
        l.aiChatFilePages('${a.pageCount}')
      else if (a.fileKind == ChatFileKind.pptx && a.pageCount != null)
        l.aiChatFileSlides('${a.pageCount}'),
      if (a.fileKind != ChatFileKind.image)
        l.aiChatAttachmentChars(
          NumberFormat.decimalPattern(locale).format(a.charCount),
        ),
      if (a.isCompressed) l.aiChatAttachmentCondensed,
      DateFormat.Md(locale).format(a.createdAt.toLocal()),
    ];
    final ready = a.status == ChatAttachmentStatus.ready;
    final tooLong = a.tokenCount > chatMaxSelectedTokens;
    final cost = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    ).format(a.tokenCount / 10000 * chatCreditsPer10kTokens);

    Widget action({
      required IconData icon,
      required String label,
      String? hint,
      required VoidCallback? onTap,
      bool primary = false,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: onTap == null
                  ? c.stageText
                  : primary
                  ? c.accent
                  : c.actionForeground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: onTap == null
                          ? c.stageText
                          : c.actionForegroundStrong,
                      fontSize: 13.5,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: TextStyle(
                        color: c.stageText,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: a.selected ? c.accent.withValues(alpha: .07) : c.chipBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.selected ? c.accent.withValues(alpha: .35) : c.chipBorder,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RowIcon(colors: c, attachment: a),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatAttachmentTitle(l, a),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.actionForegroundStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (a.summary != null && a.summary!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              a.summary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.quoteText,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta.join('・'),
                            style: TextStyle(
                              color: c.stageText,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (pending != null)
                        Text(
                          pending == ChatAttachmentMode.full
                              ? l.aiChatAttachPendingFull
                              : l.aiChatAttachPendingMention,
                          style: TextStyle(color: c.accent, fontSize: 11),
                        )
                      else if (a.selected)
                        Text(
                          l.aiChatAttachPinned,
                          style: TextStyle(color: c.accent, fontSize: 11),
                        ),
                      ChatAttachmentStatusBadge(status: a.status, colors: c),
                    ],
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: c.actionForeground,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Column(
                children: [
                  if (ready &&
                      !a.selected &&
                      a.kind != 'image')
                    action(
                      icon: Icons.layers_outlined,
                      label: l.aiChatAttachFull,
                      primary: true,
                      hint: tooLong
                          ? l.aiChatAttachmentTooLongToSelect
                          : '${l.aiChatAttachmentTokens(tokens(a.tokenCount))} · ${l.aiChatAttachmentCostPerTurn(cost)}',
                      onTap: tooLong || busy
                          ? null
                          : onPin,
                    ),
                  if (ready && pending != ChatAttachmentMode.mention)
                    action(
                      icon: Icons.alternate_email_rounded,
                      label: l.aiChatAttachMention,
                      hint: l.aiChatAttachMentionHint,
                      onTap: () => onAttach(ChatInsertMode.mention),
                    ),
                  if (pending != null)
                    action(
                      icon: Icons.close_rounded,
                      label: l.aiChatAttachUndo,
                      onTap: () => onAttach(ChatInsertMode.remove),
                    ),
                  action(
                    icon: Icons.menu_book_outlined,
                    label: l.aiChatAttachView,
                    onTap: onView,
                  ),
                  if (a.selected)
                    action(
                      icon: Icons.close_rounded,
                      label: l.aiChatAttachmentUnselect,
                      hint: l.aiChatAttachUnpinHint,
                      onTap: busy ? null : onUnpin,
                    ),
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                      child: Text(
                        l.aiChatAttachmentSelectFailed,
                        style: TextStyle(color: c.danger, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一覧の行の左: 画像は小さな見本、それ以外は種類のアイコン。
class _RowIcon extends ConsumerWidget {
  const _RowIcon({required this.colors, required this.attachment});

  final ChatColors colors;
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    Widget icon() => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        chatAttachmentIcon(attachment.kind),
        size: 19,
        color: c.accent,
      ),
    );
    if (attachment.fileKind != ChatFileKind.image ||
        attachment.status != ChatAttachmentStatus.ready) {
      return icon();
    }
    final link = ref.watch(chatAttachmentFileLinkProvider(attachment.id));
    return link.maybeWhen(
      data: (data) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          data.url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => icon(),
        ),
      ),
      orElse: icon,
    );
  }
}
