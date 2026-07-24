// lib/presentation/pages/lecture_viewer/widgets/topic_preview_card.dart

import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';

class TopicPreviewCard extends StatelessWidget {
  const TopicPreviewCard({
    super.key,
    required this.segment,
    required this.onTap,
  });

  final LectureSegment segment;
  final VoidCallback onTap;

  String _getPreviewText(String content) {
    // 引用タグを除去
    final clean = content.replaceAll(RegExp(r'⟦s.*?⟧'), '').replaceAll('#', '');
    // 最初の100文字程度を表示
    if (clean.length > 120) {
      return '${clean.substring(0, 120).trim()}...';
    }
    return clean.trim();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Index & Title
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${segment.idx}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      segment.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Body Preview
              Text(
                _getPreviewText(segment.detailContent),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              
              // Footer: Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.bookmark_border),
                    onPressed: () {}, // Dummy
                    tooltip: l10n.topicPreviewSaveTooltip,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () {}, // Dummy
                    tooltip: l10n.topicPreviewLikeTooltip,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: onTap,
                    child: Text(l10n.topicPreviewReadNoteButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}