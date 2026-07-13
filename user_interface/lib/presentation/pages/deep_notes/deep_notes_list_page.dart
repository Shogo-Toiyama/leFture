// lib/presentation/pages/deep_notes/deep_notes_list_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';


// ---------------------------------------------------------------------------
// Private data class (mirrors old _NoteTopic)
// ---------------------------------------------------------------------------
class DeepNoteTopic {
  const DeepNoteTopic({
    required this.index,
    required this.title,
    required this.summary,
    required this.content,
  });

  final int index;
  final String title;
  final String summary;
  final String content;
}

// ---------------------------------------------------------------------------
// List Page
// ---------------------------------------------------------------------------
class DeepNotesListPage extends HookConsumerWidget {
  const DeepNotesListPage({super.key, required this.lectureId});

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final lecture = lectureAsync.asData?.value;
    final courseId = lecture?.courseId ?? 'N/A';

    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final notesAsync  = ref.watch(deepNotesProvider(lectureId));

    final topics = useMemoized(() {
      final rawTopics = topicsAsync.asData?.value ?? <LectureTopic>[];
      final notes     = notesAsync.asData?.value  ?? <DeepNote>[];
      final noteMap   = {for (final n in notes) n.topicNumber: n};

      return rawTopics.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        final note = noteMap[t.index];
        return DeepNoteTopic(
          index: i,
          title: t.displayTitle,
          summary: t.summary ?? '',
          content: note?.noteContents ?? '',
        );
      }).toList();
    }, [topicsAsync, notesAsync]);

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(
              showHomeButton: true,
              title: 'Deep Notes',
              isLightBg: true,
            ),
            Expanded(
              child: _buildBody(context, topics, notesAsync.isLoading || topicsAsync.isLoading, courseId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<DeepNoteTopic> topics,
    bool isLoading,
    String courseId,
  ) {
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold));
    }

    if (topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: AppColors.paper.textPencil),
            const SizedBox(height: 16),
            Text(
              'Deep notes are being generated…',
              style:
                  TextStyle(color: AppColors.paper.textPencil, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: topics.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final topic = topics[index];
        final hasContent = topic.content.trim().isNotEmpty;
        return GestureDetector(
          onTap: () => context.push(
              '${AppRoutes.coursesRootPath}/c/$courseId/dnd/$lectureId/${topic.index}',
              extra: topics),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.paper.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.black.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Index badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.deepGold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.deepGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (topic.summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          topic.summary,
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  hasContent
                      ? Icons.chevron_right
                      : Icons.hourglass_empty_outlined,
                  color: hasContent
                      ? AppColors.deepGold
                      : AppColors.paper.textPencil,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
