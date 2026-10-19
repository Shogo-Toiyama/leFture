// lib/presentation/widgets/ai_chat/chat_composer_parts.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_drafts.dart';
import 'package:lefture/core/utils/chat_composer_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';

/// 資料の種類のアイコン(webappの AttachmentKindIcon)。
IconData chatAttachmentIcon(String? kind) => switch (kind) {
  'image' => Icons.image_outlined,
  'pptx' => Icons.slideshow_rounded,
  'pdf' || 'docx' => Icons.description_outlined,
  _ => Icons.attach_file_rounded,
};

/// 資料の名前(無ければファイル名、それも無ければ「資料」)。
String chatAttachmentTitle(AppLocalizations l, ChatAttachment a) {
  final title = a.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final file = a.fileName?.trim();
  if (file != null && file.isNotEmpty) return file;
  return l.aiChatAttachmentUntitled;
}

/// 下書きのチップに出す名前(名前が無ければ、本文の最初の行・ファイル名)。
String chatDraftLabel(ChatDraft draft) {
  if (draft.title.trim().isNotEmpty) return draft.title.trim();
  return switch (draft) {
    ChatFileDraft() => draft.fileName,
    ChatTextDraft() =>
      draft.content
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => ''),
  };
}

String _formatNumber(BuildContext context, num n) =>
    NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(n);

/// ファイルのチップの右側(段階・ページ数・エラー)。
String chatFileDraftMeta(BuildContext context, ChatFileDraft draft) {
  final l = AppLocalizations.of(context);
  switch (draft.stage) {
    case ChatFileStage.compressing:
      return l.aiChatFileCompressing;
    case ChatFileStage.uploading:
      return l.aiChatFileUploading('${((draft.progress ?? 0) * 100).round()}');
    case ChatFileStage.reading:
      return l.aiChatFileReading;
    case ChatFileStage.error:
      return chatFileErrorCopy(l, draft.errorCode, draft.errorDetail);
    case ChatFileStage.ready:
      final info = draft.info;
      if (info == null) return '';
      final parts = <String>[];
      if (info.kind == ChatFileKind.image) {
        parts.add(l.aiChatFileImage);
      } else if (info.kind == ChatFileKind.pdf && info.pageCount != null) {
        parts.add(l.aiChatFilePages('${info.pageCount}'));
      } else if (info.kind == ChatFileKind.pptx && info.pageCount != null) {
        parts.add(l.aiChatFileSlides('${info.pageCount}'));
      } else {
        parts.add(
          l.aiChatAttachmentChars(_formatNumber(context, info.textChars)),
        );
      }
      if (info.kind != ChatFileKind.image && info.visionCount > 0) {
        parts.add(l.aiChatFileVisionCount('${info.visionCount}'));
      }
      return parts.join(' · ');
  }
}

/// 入力欄の上のチップの形(丸い枠・左に見本かアイコン・名前・右に補足・×)。
class _ChipFrame extends StatelessWidget {
  const _ChipFrame({
    required this.colors,
    required this.child,
    this.onTap,
    this.onRemove,
    this.removeLabel,
    this.accentBorder = false,
    this.progress,
  });

  final ChatColors colors;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? removeLabel;
  final bool accentBorder;

  /// アップロードの進み具合(0〜1)。チップの下に細い線で出す。
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final border = accentBorder
        ? c.accent.withValues(alpha: .35)
        : c.chipBorder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.chipBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                      child: child,
                    ),
                  ),
                ),
                if (onRemove != null)
                  InkResponse(
                    onTap: onRemove,
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: c.actionForeground,
                        semanticLabel: removeLabel,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: c.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  const _ChipText({required this.colors, required this.label, this.meta});

  final ChatColors colors;
  final String label;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.chipText, fontSize: 12.2),
            ),
          ),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                meta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.stageText, fontSize: 11),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 送る前の資料(テキスト・ファイル)のチップ。押すと中身を見る/直す、×で外す。
class ChatDraftChip extends StatelessWidget {
  const ChatDraftChip({
    super.key,
    required this.draft,
    required this.colors,
    required this.onOpen,
    required this.onRemove,
  });

  final ChatDraft draft;
  final ChatColors colors;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = draft;
    final c = colors;
    Widget lead;
    String meta;
    double? progress;
    if (d is ChatFileDraft) {
      meta = chatFileDraftMeta(context, d);
      progress = d.stage == ChatFileStage.uploading ? (d.progress ?? 0) : null;
      if (d.previewBytes != null) {
        lead = ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            d.previewBytes!,
            width: 20,
            height: 20,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // 見本が読めなくても、チップは使える
            errorBuilder: (_, _, _) =>
                Icon(Icons.image_outlined, size: 15, color: c.accent),
          ),
        );
      } else if (d.stage == ChatFileStage.error) {
        lead = Icon(Icons.error_outline_rounded, size: 15, color: c.danger);
      } else if (d.stage == ChatFileStage.ready) {
        lead = Icon(
          chatAttachmentIcon(d.fileKind.name),
          size: 15,
          color: c.accent,
        );
      } else {
        lead = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: c.accent),
        );
      }
    } else {
      d as ChatTextDraft;
      meta = l.aiChatAttachmentChars(_formatNumber(context, d.content.length));
      lead = Icon(Icons.attach_file_rounded, size: 15, color: c.accent);
    }
    return Semantics(
      label: chatDraftLabel(d),
      child: _ChipFrame(
        colors: c,
        accentBorder: d is! ChatFileDraft || d.stage != ChatFileStage.error,
        onTap: onOpen,
        onRemove: onRemove,
        removeLabel: l.aiChatRemoveAttachment,
        progress: progress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lead,
            const SizedBox(width: 6),
            Flexible(
              child: _ChipText(colors: c, label: chatDraftLabel(d), meta: meta),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全文で読んでいる資料のチップ(×で、全文で読むのをやめる)。
class ChatPinnedChip extends StatelessWidget {
  const ChatPinnedChip({
    super.key,
    required this.attachment,
    required this.colors,
    required this.onUnpin,
  });

  final ChatAttachment attachment;
  final ChatColors colors;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _ChipFrame(
      colors: colors,
      accentBorder: true,
      onRemove: onUnpin,
      removeLabel: l.aiChatAttachmentUnselect,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            chatAttachmentIcon(attachment.kind),
            size: 15,
            color: colors.accent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: _ChipText(
              colors: colors,
              label: chatAttachmentTitle(l, attachment),
              meta: l.aiChatAttachPinned,
            ),
          ),
        ],
      ),
    );
  }
}

/// 入力欄の「@名前」にカーソルがあるときの操作(中身を見る・全文⇄メンション・外す)。
class ChatMentionActionBar extends StatelessWidget {
  const ChatMentionActionBar({
    super.key,
    required this.colors,
    required this.mention,
    required this.title,
    required this.kind,
    required this.thumb,
    required this.onView,
    required this.onToggleMode,
    required this.onRemove,
  });

  final ChatColors colors;
  final ComposerMention mention;
  final String title;
  final String? kind;
  final ImageProvider? thumb;
  final VoidCallback onView;
  final VoidCallback onToggleMode;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final target = mention.target;
    final isNew = target is DraftMention;
    final full =
        isNew ||
        (target is ExistingMention && target.mode == ChatAttachmentMode.full);
    final tag = isNew
        ? l.aiChatMentionNewFull
        : full
        ? l.aiChatAttachFull
        : l.aiChatAttachMention;
    Widget action(String label, VoidCallback onTap, {Color? color}) =>
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: color ?? c.accent,
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
      decoration: BoxDecoration(
        color: c.menuBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.menuBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (thumb != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image(
                    image: thumb!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      chatAttachmentIcon(kind),
                      size: 18,
                      color: c.accent,
                    ),
                  ),
                )
              else
                Icon(chatAttachmentIcon(kind), size: 18, color: c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.actionForegroundStrong,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.stageText, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              InkResponse(
                onTap: onRemove,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: c.danger,
                    semanticLabel: l.aiChatRemoveAttachment,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            children: [
              action(l.aiChatAttachView, onView),
              if (!isNew)
                action(
                  full ? l.aiChatMentionToMention : l.aiChatMentionToFull,
                  onToggleMode,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「@」を打ったときの資料の候補。名前を押すとメンション、「全文で添付」を押すと全文。
class ChatMentionPicker extends StatelessWidget {
  const ChatMentionPicker({
    super.key,
    required this.colors,
    required this.items,
    required this.onPick,
  });

  final ChatColors colors;
  final List<ChatAttachment> items;
  final void Function(ChatAttachment attachment, ChatAttachmentMode mode)
  onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: c.menuBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.menuBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.alternate_email_rounded,
                  size: 14,
                  color: c.stageText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.aiChatMentionPickerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.stageText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Text(
                l.aiChatMentionPickerEmpty,
                style: TextStyle(color: c.stageText, fontSize: 13),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                children: [
                  for (final a in items)
                    _PickerRow(
                      colors: c,
                      attachment: a,
                      onPick: (mode) => onPick(a, mode),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.colors,
    required this.attachment,
    required this.onPick,
  });

  final ChatColors colors;
  final ChatAttachment attachment;
  final void Function(ChatAttachmentMode mode) onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final tooLong = attachment.tokenCount > chatMaxSelectedTokens;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onPick(ChatAttachmentMode.mention),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    chatAttachmentIcon(attachment.kind),
                    size: 16,
                    color: c.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatAttachmentTitle(l, attachment),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.actionForegroundStrong,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (attachment.selected) ...[
                    const SizedBox(width: 6),
                    Text(
                      l.aiChatAttachPinned,
                      style: TextStyle(color: c.accent, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!attachment.selected)
          Tooltip(
            message: tooLong
                ? l.aiChatAttachmentTooLongToSelect
                : l.aiChatAttachFullHint,
            child: TextButton(
              onPressed: tooLong ? null : () => onPick(ChatAttachmentMode.full),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: c.accent,
              ),
              child: Text(
                l.aiChatAttachFull,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}
