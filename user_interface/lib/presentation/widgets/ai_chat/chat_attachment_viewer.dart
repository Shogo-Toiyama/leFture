// lib/presentation/widgets/ai_chat/chat_attachment_viewer.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_attachment_files.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

/// 資料の状態(確認中・使えなかった)の小さな印。使える資料(ready)には出さない。
class ChatAttachmentStatusBadge extends StatelessWidget {
  const ChatAttachmentStatusBadge({
    super.key,
    required this.status,
    required this.colors,
  });

  final ChatAttachmentStatus status;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = switch (status) {
      ChatAttachmentStatus.ready || ChatAttachmentStatus.draft => null,
      ChatAttachmentStatus.processing => l.aiChatAttachmentProcessing,
      ChatAttachmentStatus.blocked => l.aiChatAttachmentBlocked,
      ChatAttachmentStatus.failed => l.aiChatAttachmentFailed,
    };
    if (label == null) return const SizedBox.shrink();
    final bad =
        status == ChatAttachmentStatus.blocked ||
        status == ChatAttachmentStatus.failed;
    final tint = bad ? colors.danger : colors.stageText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 送った資料を読む(編集はできない)。目次があれば、押すとその節の本文へ飛ぶ。
/// ファイルの資料は、元のファイルも開ける(PDFはアプリの中、Word・PowerPointは端末の対応アプリで)。
/// [onRemove]を渡すと「この会話から外す」を出す(送った資料のときだけ)。
Future<void> showChatAttachmentViewer(
  BuildContext context, {
  required ChatColors colors,
  required ChatAttachment attachment,
  Future<void> Function()? onRemove,
}) {
  return showChatSheet<void>(
    context,
    colors,
    (_) => _AttachmentViewer(
      colors: colors,
      attachment: attachment,
      onRemove: onRemove,
    ),
  );
}

class _AttachmentViewer extends ConsumerStatefulWidget {
  const _AttachmentViewer({
    required this.colors,
    required this.attachment,
    required this.onRemove,
  });

  final ChatColors colors;
  final ChatAttachment attachment;
  final Future<void> Function()? onRemove;

  @override
  ConsumerState<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends ConsumerState<_AttachmentViewer> {
  final _scroll = ScrollController();
  late final _sectionKeys = <int, GlobalKey>{};
  bool _confirmingRemove = false;
  bool _removing = false;
  bool _removeFailed = false;
  bool _openingFile = false;
  bool _openFailed = false;

  ChatAttachment get _a => widget.attachment;
  bool get _isImage => _a.fileKind == ChatFileKind.image;
  bool get _hasFile => _a.kind != 'text';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openOriginal() async {
    setState(() {
      _openingFile = true;
      _openFailed = false;
    });
    try {
      final link = await ref.read(chatAttachmentFileLinkProvider(_a.id).future);
      if (!mounted) return;
      if (_a.fileKind == ChatFileKind.pdf) {
        await showChatPdfViewer(
          context,
          colors: widget.colors,
          uri: Uri.parse(link.url),
          title: _title(AppLocalizations.of(context)),
        );
      } else {
        final ok = await launchUrl(
          Uri.parse(link.url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && mounted) setState(() => _openFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _openFailed = true);
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  Future<void> _remove() async {
    final onRemove = widget.onRemove;
    if (onRemove == null) return;
    setState(() {
      _removing = true;
      _removeFailed = false;
    });
    try {
      await onRemove();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _removeFailed = true);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  String _title(AppLocalizations l) => chatAttachmentTitle(l, _a);

  void _jumpTo(int index) {
    final ctx = _sectionKeys[index]?.currentContext;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final locale = Localizations.localeOf(context).toString();
    String fmt(num n) => NumberFormat.decimalPattern(locale).format(n);
    final a = _a;
    final sections = a.sections;
    final meta = <String>[
      if (a.fileKind == ChatFileKind.pdf && a.pageCount != null)
        l.aiChatFilePages('${a.pageCount}')
      else if (a.fileKind == ChatFileKind.pptx && a.pageCount != null)
        l.aiChatFileSlides('${a.pageCount}'),
      if (a.content.isNotEmpty) l.aiChatAttachmentChars(fmt(a.content.length)),
    ];
    final textStyle = TextStyle(color: c.text, fontSize: 13.5, height: 1.7);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatSheetHeader(
            colors: c,
            icon: chatAttachmentIcon(a.kind),
            badge: l.aiChatSourceAttachment,
            badgeMeta: meta.isEmpty ? null : meta.join(' · '),
            title: _title(l),
          ),
          if (a.status != ChatAttachmentStatus.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChatAttachmentStatusBadge(status: a.status, colors: c),
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              children: [
                if (_isImage) _ImagePreview(attachmentId: a.id, colors: c),
                if (a.summary != null && a.summary!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      a.summary!,
                      style: textStyle.copyWith(color: c.quoteText),
                    ),
                  ),
                if (sections.length > 1)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      iconColor: c.actionForeground,
                      collapsedIconColor: c.actionForeground,
                      title: Text(
                        l.aiChatAttachmentContentsCount('${sections.length}'),
                        style: TextStyle(
                          color: c.actionForegroundStrong,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        for (final s in sections)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onTap: () => _jumpTo(s.index),
                            title: Text(
                              s.title,
                              style: TextStyle(
                                color: c.actionForegroundStrong,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: s.description.isEmpty
                                ? null
                                : Text(
                                    s.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.stageText,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                if (a.content.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(
                      l.aiChatAttachmentFullText,
                      style: TextStyle(
                        color: c.stageText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (sections.length > 1)
                    for (final s in sections)
                      Padding(
                        key: _sectionKeys.putIfAbsent(s.index, GlobalKey.new),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.index}. ${s.title}',
                              style: TextStyle(
                                color: c.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              a.content
                                  .substring(
                                    s.start.clamp(0, a.content.length),
                                    s.end.clamp(0, a.content.length),
                                  )
                                  .trim(),
                              style: textStyle,
                            ),
                          ],
                        ),
                      )
                  else
                    SelectableText(a.content, style: textStyle),
                ],
              ],
            ),
          ),
          _footer(l, c),
        ],
      ),
    );
  }

  Widget _footer(AppLocalizations l, ChatColors c) {
    final close = TextButton(
      onPressed: () => Navigator.of(context).maybePop(),
      child: Text(l.aiChatClose, style: TextStyle(color: c.actionForeground)),
    );
    Widget errorLine(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.danger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_openFailed) errorLine(l.aiChatAttachmentOpenFileFailed),
          if (_removeFailed) errorLine(l.aiChatAttachmentRemoveFailed),
          if (_confirmingRemove) ...[
            Text(
              l.aiChatAttachmentRemoveConfirm,
              style: TextStyle(color: c.text, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _confirmingRemove = false),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                    style: TextStyle(color: c.actionForeground),
                  ),
                ),
                TextButton(
                  onPressed: _removing ? null : _remove,
                  child: Text(
                    l.aiChatAttachmentRemove,
                    style: TextStyle(color: c.danger),
                  ),
                ),
              ],
            ),
          ] else
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (_hasFile && !_isImage)
                  TextButton.icon(
                    onPressed: _openingFile ? null : _openOriginal,
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 15,
                      color: c.accent,
                    ),
                    label: Text(
                      l.aiChatAttachmentOpenFile,
                      style: TextStyle(color: c.accent),
                    ),
                  ),
                if (widget.onRemove != null)
                  TextButton(
                    onPressed: () => setState(() => _confirmingRemove = true),
                    child: Text(
                      l.aiChatAttachmentRemove,
                      style: TextStyle(color: c.danger),
                    ),
                  ),
                close,
              ],
            ),
        ],
      ),
    );
  }
}

/// 画像の資料の本体(署名付きURLを頼んで表示する。ピンチで拡大できる)。
class _ImagePreview extends ConsumerWidget {
  const _ImagePreview({required this.attachmentId, required this.colors});

  final String attachmentId;
  final ChatColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final link = ref.watch(chatAttachmentFileLinkProvider(attachmentId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: link.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              l.aiChatAttachmentImageLoading,
              style: TextStyle(color: colors.stageText, fontSize: 13),
            ),
          ),
        ),
        error: (_, _) => Text(
          l.aiChatAttachmentOpenFileFailed,
          style: TextStyle(color: colors.danger, fontSize: 13),
        ),
        data: (data) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              data.url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l.aiChatAttachmentOpenFileFailed,
                  style: TextStyle(color: colors.danger, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 送ったPDFを、アプリの中で開く。
Future<void> showChatPdfViewer(
  BuildContext context, {
  required ChatColors colors,
  required Uri uri,
  required String title,
}) {
  return showChatSheet<void>(
    context,
    colors,
    (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .94,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatSheetHeader(
            colors: colors,
            icon: Icons.description_outlined,
            badge: 'PDF',
            title: title,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: PdfViewer.uri(
                uri,
                params: PdfViewerParams(backgroundColor: colors.preBackground),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
