// lib/presentation/pages/lecture_viewer/lecture_viewer_page.dart

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_note/lecture_note_page.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/widgets/topic_preview_card.dart';

class LectureViewerPage extends HookConsumerWidget {
  const LectureViewerPage({
    super.key,
    required this.lecture,
  });

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please sign in')));

    // JSONデータの取得
    final completeDataAsync = ref.watch(
      lectureCompleteDataProvider(uid: uid, lectureId: lecture.id),
    );

    // 日付フォーマット
    final dateStr = DateFormat.yMMMd().format(lecture.lectureDatetime);
    final timeStr = DateFormat.Hm().format(lecture.lectureDatetime);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lecture Overview'),
        centerTitle: false,
      ),
      body: completeDataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (data) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Breadcrumb (Dummy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.folder_open, size: 16, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 8),
                        Text(
                          'Notes / CS181 / Week 3', // TODO: 実際のパンくずを表示できるようにする
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ),

                  // 2. Title & Speaker
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lecture.title ?? 'Untitled Lecture',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () {}, // Dummy
                        icon: const Icon(Icons.record_voice_over),
                        tooltip: 'Play Audio / Transcript',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 3. Date & Time
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('$dateStr  •  $timeStr'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4. Summary (Dummy)
                  _buildSectionHeader(context, 'Summary'),
                  const Text(
                    'This lecture covers the fundamental concepts of Python programming, focusing on functional programming paradigms. Key topics include lambda functions, map/reduce, and list comprehensions.',
                  ),
                  const SizedBox(height: 24),

                  // 5. Announcements (Dummy)
                  _buildSectionHeader(context, 'Announcements', icon: Icons.campaign),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onTertiaryContainer),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Midterm exam will be held next Tuesday. Please review Chapter 4.'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 6. Topics (List of Cards)
                  _buildSectionHeader(context, 'Topics'),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.segments.length,
                    itemBuilder: (context, index) {
                      final segment = data.segments[index];
                      return TopicPreviewCard(
                        segment: segment,
                        onTap: () {
                          // 詳細ページへ遷移
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LectureNotePage(
                                lecture: lecture,
                                segment: segment,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}