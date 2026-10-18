// lib/presentation/widgets/ai_chat/chat_citation_sheet.dart
import 'package:flutter/material.dart';
import 'package:lefture/core/utils/chat_citation_target.dart';
import 'package:lefture/core/utils/chat_markdown_text.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_markdown.dart';

IconData _sourceIcon(String type) => switch (type) {
  'transcript_topic' => Icons.article_outlined,
  'deep_note' ||
  'course' ||
  'topic_summary' ||
  'lecture_summary' => Icons.menu_book_outlined,
  'review_card' => Icons.layers_outlined,
  'announcement' => Icons.notifications_none_rounded,
  'keyword' || 'fun_fact' || 'lecture_moment' => Icons.auto_awesome_outlined,
  'chat_turn' => Icons.chat_bubble_outline_rounded,
  'web' => Icons.public_rounded,
  'chat_attachment' => Icons.attach_file_rounded,
  _ => Icons.menu_book_outlined,
};

/// 出典の抜粋のシート(webappのCitationPreviewModal)。押された引用の区切りがあれば、その箇所を
/// 前後の文脈つきで光らせて見せる。行き先があれば「講義ページで全体を見る」などのボタンを出す。
/// ボタンを押すと、シートを閉じてから[onOpenTarget]を呼ぶ。
Future<void> showChatCitationSheet(
  BuildContext context, {
  required ChatColors colors,
  required ChatCitation citation,
  List<String> specs = const [],
  void Function(ChatCitationTarget target)? onOpenTarget,
}) {
  return showChatSheet<void>(
    context,
    colors,
    (_) => _CitationSheet(
      colors: colors,
      citation: citation,
      specs: specs,
      onOpenTarget: onOpenTarget,
    ),
  );
}

class _CitationSheet extends StatelessWidget {
  const _CitationSheet({
    required this.colors,
    required this.citation,
    required this.specs,
    required this.onOpenTarget,
  });

  final ChatColors colors;
  final ChatCitation citation;
  final List<String> specs;
  final void Function(ChatCitationTarget target)? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final target = chatCitationTarget(citation);
    final isWeb = citation.sourceType == 'web';
    final parts = citation.label
        .split(' / ')
        .where((p) => p.isNotEmpty)
        .toList();
    final courseOrSite = isWeb
        ? (citation.metadata['domain'] as String? ?? '')
        : (parts.isNotEmpty ? parts[0] : '');
    final lectureTitle = isWeb ? '' : (parts.length > 1 ? parts[1] : '');
    final detailTitle = parts.length >= 3
        ? parts.skip(2).join(' · ')
        : (parts.length > 1 ? parts[1] : citation.label);
    final range = citation.metadata['sentence_range'];
    final subtitle = [
      courseOrSite,
      lectureTitle,
    ].where((s) => s.isNotEmpty).join(' · ');

    // 引用された区切り。無ければ従来どおり出典の抜粋を見せる
    final passages = [
      for (final s in specs)
        if (citation.passages[s] != null) citation.passages[s]!,
    ];

    final Widget body;
    if (passages.isNotEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in passages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: c.text, fontSize: 14, height: 1.7),
                  children: [
                    if (p.before.isNotEmpty)
                      TextSpan(
                        text: '${markdownToPlainText(p.before)} ',
                        style: TextStyle(color: c.stageText),
                      ),
                    TextSpan(
                      text: markdownToPlainText(p.text),
                      style: TextStyle(
                        backgroundColor: c.citeBackground,
                        color: c.strongText,
                      ),
                    ),
                    if (p.after.isNotEmpty)
                      TextSpan(
                        text: ' ${markdownToPlainText(p.after)}',
                        style: TextStyle(color: c.stageText),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else if (citation.snippet != null && citation.snippet!.isNotEmpty) {
      body = ChatMarkdown(markdown: citation.snippet!, colors: c, fontSize: 14);
    } else {
      body = Text(
        l.aiChatSourcePreviewEmpty,
        style: TextStyle(color: c.stageText, fontSize: 13.5, height: 1.6),
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatSheetHeader(
            colors: c,
            icon: _sourceIcon(citation.sourceType),
            badge:
                '${citation.ref}  ${chatSourceKindLabel(l, citation.sourceType)}',
            badgeMeta: range is String ? range : null,
            title: detailTitle,
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.stageText, fontSize: 12.5),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SelectionArea(child: body),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    l.aiChatClose,
                    style: TextStyle(color: c.actionForeground),
                  ),
                ),
                if (target != null && onOpenTarget != null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenTarget!(target);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      target is CitationWebTarget
                          ? Icons.open_in_new_rounded
                          : Icons.arrow_forward_rounded,
                      size: 16,
                    ),
                    label: Text(
                      target is CitationWebTarget
                          ? l.aiChatOpenExternalWeb
                          : target is CitationThreadTarget
                          ? l.aiChatSourceChat
                          : l.aiChatOpenInLecture,
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
