// lib/presentation/widgets/ai_chat/chat_draft_sheets.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_drafts.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:pdfrx/pdfrx.dart';

/// 送る前の資料のシート(テキストを書く・直す / ファイルの中身を確かめる)。
/// webappの AttachmentEditorModal と DraftPreviewModal。

/// チャットの下から出るシート(資料の編集・一覧・ビューアで共通)。
Future<T?> showChatSheet<T>(
  BuildContext context,
  ChatColors colors,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.menuBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// シートの上の見出し(種類のバッジ・題名・閉じる)。
class ChatSheetHeader extends StatelessWidget {
  const ChatSheetHeader({
    super.key,
    required this.colors,
    required this.icon,
    required this.badge,
    required this.title,
    this.badgeMeta,
  });

  final ChatColors colors;
  final IconData icon;
  final String badge;
  final String? badgeMeta;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: c.accent),
                    const SizedBox(width: 5),
                    Text(
                      badge,
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (badgeMeta != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          badgeMeta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.stageText, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.strongText,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: l.aiChatClose,
            icon: Icon(Icons.close_rounded, color: c.actionForeground),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// テキストの資料を書く・直す
// ---------------------------------------------------------------------------

typedef ChatTextDraftValue = ({String title, String content});

/// テキストの資料を添付する(送るまでは何度でも直せる)。保存すると名前と本文を返す。
/// 送った後は編集できない(バックエンドが審査・目次づくりをした中身だけを使うため)。
Future<ChatTextDraftValue?> showChatTextDraftSheet(
  BuildContext context, {
  required ChatColors colors,
  String initialTitle = '',
  String initialContent = '',
  bool editing = false,
  bool fromPaste = false,
}) {
  return showChatSheet<ChatTextDraftValue>(
    context,
    colors,
    (_) => _TextDraftSheet(
      colors: colors,
      initialTitle: initialTitle,
      initialContent: initialContent,
      editing: editing,
      fromPaste: fromPaste,
    ),
  );
}

class _TextDraftSheet extends StatefulWidget {
  const _TextDraftSheet({
    required this.colors,
    required this.initialTitle,
    required this.initialContent,
    required this.editing,
    required this.fromPaste,
  });

  final ChatColors colors;
  final String initialTitle;
  final String initialContent;
  final bool editing;
  final bool fromPaste;

  @override
  State<_TextDraftSheet> createState() => _TextDraftSheetState();
}

class _TextDraftSheetState extends State<_TextDraftSheet> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _content = TextEditingController(text: widget.initialContent);

  @override
  void initState() {
    super.initState();
    _content.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final locale = Localizations.localeOf(context).toString();
    String fmt(int n) => NumberFormat.decimalPattern(locale).format(n);
    final length = _content.text.length;
    final trimmed = _content.text.trim();
    final over = length > chatMaxAttachmentChars;
    final canSave = trimmed.isNotEmpty && !over;
    final heading = widget.editing
        ? l.aiChatAttachmentEditorEditTitle
        : l.aiChatAttachmentEditorTitle;
    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.hintText),
      isDense: true,
      filled: true,
      fillColor: c.inputBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.accent),
      ),
      counterText: '',
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatSheetHeader(
              colors: c,
              icon: Icons.attach_file_rounded,
              badge: l.aiChatAttachLongText,
              title: heading,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.fromPaste)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          l.aiChatAttachmentPasteNotice(
                            fmt(chatMaxMessageChars),
                          ),
                          style: TextStyle(
                            color: c.noticeText,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    TextField(
                      controller: _title,
                      maxLength: chatMaxAttachmentTitleChars,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: c.text, fontSize: 14.5),
                      cursorColor: c.accent,
                      decoration: decoration(
                        l.aiChatAttachmentTitlePlaceholder,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TextField(
                        controller: _content,
                        autofocus: widget.initialContent.isEmpty,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        cursorColor: c.accent,
                        decoration:
                            decoration(
                              l.aiChatAttachmentContentPlaceholder,
                            ).copyWith(
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: over ? c.danger : c.inputBorder,
                                ),
                              ),
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              l.aiChatAttachmentEditorNote,
                              style: TextStyle(
                                color: c.stageText,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            over
                                ? l.aiChatAttachmentTooLong(
                                    fmt(chatMaxAttachmentChars),
                                  )
                                : '${fmt(length)} / ${fmt(chatMaxAttachmentChars)}',
                            style: TextStyle(
                              color: over ? c.danger : c.stageText,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                      style: TextStyle(color: c.actionForeground),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canSave
                        ? () => Navigator.of(
                            context,
                          ).pop((title: _title.text.trim(), content: trimmed))
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.attach_file_rounded, size: 16),
                    label: Text(
                      widget.editing
                          ? l.aiChatAttachmentSave
                          : l.aiChatAttachmentAdd,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 送る前のファイルの中身を確かめる
// ---------------------------------------------------------------------------

/// 送る前のファイルの中身を確かめる(入力欄のチップ・「@名前」から開く)。画像はそのまま、PDFは端末の
/// ファイルをアプリの中で表示する。Word・PowerPointは表示できないので、取り出して分かったこと
/// (ページ数・文字数・画像として読む数)を見せる(送った後は資料のビューアで本文と元のファイルを開ける)。
Future<void> showChatDraftPreviewSheet(
  BuildContext context, {
  required ChatColors colors,
  required ChatDraftsController drafts,
  required String localId,
  required VoidCallback onRemove,
}) {
  return showChatSheet<void>(
    context,
    colors,
    (_) => _DraftPreviewSheet(
      colors: colors,
      drafts: drafts,
      localId: localId,
      onRemove: onRemove,
    ),
  );
}

class _DraftPreviewSheet extends StatelessWidget {
  const _DraftPreviewSheet({
    required this.colors,
    required this.drafts,
    required this.localId,
    required this.onRemove,
  });

  final ChatColors colors;
  final ChatDraftsController drafts;
  final String localId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drafts,
      builder: (context, _) {
        final draft = drafts.draftById(localId);
        // 外された(準備中に×を押したなど): 閉じる
        if (draft is! ChatFileDraft) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        return _DraftPreviewBody(
          colors: colors,
          draft: draft,
          onRemove: () {
            onRemove();
            Navigator.of(context).maybePop();
          },
        );
      },
    );
  }
}

class _DraftPreviewBody extends StatelessWidget {
  const _DraftPreviewBody({
    required this.colors,
    required this.draft,
    required this.onRemove,
  });

  final ChatColors colors;
  final ChatFileDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final info = draft.info;
    final locale = Localizations.localeOf(context).toString();
    final facts = <String>[];
    if (info != null) {
      if (info.pageCount != null && info.kind == ChatFileKind.pdf) {
        facts.add(l.aiChatFilePages('${info.pageCount}'));
      }
      if (info.pageCount != null && info.kind == ChatFileKind.pptx) {
        facts.add(l.aiChatFileSlides('${info.pageCount}'));
      }
      if (info.kind != ChatFileKind.image) {
        facts.add(
          l.aiChatAttachmentChars(
            NumberFormat.decimalPattern(locale).format(info.textChars),
          ),
        );
        if (info.visionCount > 0) {
          facts.add(l.aiChatFileVisionCount('${info.visionCount}'));
        }
      }
    }
    final stage = switch (draft.stage) {
      ChatFileStage.compressing => l.aiChatFileCompressing,
      ChatFileStage.uploading => l.aiChatFileUploadingShort,
      ChatFileStage.reading => l.aiChatFileReading,
      _ => null,
    };
    Widget preview;
    if (draft.previewBytes != null) {
      preview = InteractiveViewer(
        child: Center(
          child: Image.memory(draft.previewBytes!, fit: BoxFit.contain),
        ),
      );
    } else if (draft.localPath != null && draft.fileKind == ChatFileKind.pdf) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: PdfViewer.file(
          draft.localPath!,
          params: PdfViewerParams(backgroundColor: c.preBackground),
        ),
      );
    } else if (draft.fileKind != ChatFileKind.image) {
      preview = Text(
        l.aiChatDraftPreviewOffice,
        style: TextStyle(color: c.stageText, fontSize: 13, height: 1.6),
      );
    } else {
      preview = const SizedBox.shrink();
    }
    final isPdfView =
        draft.localPath != null &&
        draft.fileKind == ChatFileKind.pdf &&
        draft.previewBytes == null;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatSheetHeader(
            colors: c,
            icon: chatAttachmentIcon(draft.fileKind.name),
            badge: l.aiChatDraftPreviewBadge,
            badgeMeta: stage,
            title: draft.fileName,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (draft.stage == ChatFileStage.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: c.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              chatFileErrorCopy(
                                l,
                                draft.errorCode,
                                draft.errorDetail,
                              ),
                              style: TextStyle(
                                color: c.danger,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isPdfView) Expanded(child: preview) else preview,
                  if (facts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        facts.join(' · '),
                        style: TextStyle(color: c.stageText, fontSize: 12.5),
                      ),
                    ),
                  if (info != null && info.visionPages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l.aiChatDraftPreviewVisionPages(
                          info.visionPages.take(20).join(', '),
                        ),
                        style: TextStyle(color: c.stageText, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onRemove,
                  child: Text(
                    l.aiChatRemoveAttachment,
                    style: TextStyle(color: c.danger),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    l.aiChatClose,
                    style: TextStyle(color: c.actionForeground),
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
