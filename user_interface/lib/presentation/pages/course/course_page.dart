import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_announcement_provider.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/topic_map/topic_map_provider.dart';
import 'package:lecture_companion_ui/application/topic_map/topic_map_reconstruct_controller.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';


import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_announcements_sheet.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_create_sheet.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_details_sheet.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/core/utils/connectivity_utils.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/cluster_view/cluster_map_view.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/cluster_view/cluster_selection.dart';

import 'package:lecture_companion_ui/presentation/widgets/course_tile.dart';
import 'package:lecture_companion_ui/presentation/widgets/lecture_tile.dart';

/// コース一覧 / コース内授業一覧 を兼ねるページ
///
/// [courseId] == null → 全コースを Year / Term でグループ表示
/// [courseId] != null → そのコースの授業一覧を表示
class CoursePage extends ConsumerWidget {
  const CoursePage({super.key, this.courseId});

  final String? courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (courseId != null) {
      return _CourseLectureListView(courseId: courseId!);
    }
    return const _CourseTreeView();
  }
}

// ---------------------------------------------------------------------------
// コース一覧（Year > Term 仮想フォルダツリー）
// ---------------------------------------------------------------------------

class _CourseTreeView extends ConsumerWidget {
  const _CourseTreeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(courseListProvider);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.starGold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Course'),
        onPressed: () => _openCreateSheet(context, ref),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(
              showHomeButton: true,
              title: 'Courses',
            ),
            Expanded(
              child: coursesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.starGold),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: AppColors.correctionRed),
                  ),
                ),
                data: (courses) {
                  if (courses.isEmpty) {
                    return _EmptyCoursesView(
                      onCreateTap: () => _openCreateSheet(context, ref),
                    );
                  }
                  final grouped = _groupCourses(courses);
                  return RefreshIndicator(
                    color: AppColors.starGold,
                    onRefresh: () => _handleRefresh(context, ref),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: grouped.entries.map((yearEntry) {
                        return _YearSection(
                          yearName: yearEntry.key,
                          termMap: yearEntry.value,
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CourseCreateSheet(),
    );
  }

  /// courses → { yearName → { termName → [Course] } }
  /// Year/Term 未設定は "No Year" / "No Term" に分類
  Map<String, Map<String, List<Course>>> _groupCourses(List<Course> courses) {
    final result = <String, Map<String, List<Course>>>{};
    for (final course in courses) {
      final yearName = course.year?.attributeName ?? 'No Year';
      final termName = course.term?.attributeName ?? 'No Term';
      result.putIfAbsent(yearName, () => {});
      result[yearName]!.putIfAbsent(termName, () => []);
      result[yearName]![termName]!.add(course);
    }
    // Year を降順（新しい年が上）、No Year は末尾
    final sorted = Map.fromEntries(
      result.entries.toList()..sort((a, b) {
        if (a.key == 'No Year') return 1;
        if (b.key == 'No Year') return -1;
        return b.key.compareTo(a.key);
      }),
    );
    return sorted;
  }
}

class _YearSection extends StatelessWidget {
  const _YearSection({required this.yearName, required this.termMap});

  final String yearName;
  final Map<String, List<Course>> termMap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Icon(Icons.folder, color: AppColors.starGold, size: 18),
              const SizedBox(width: 8),
              Text(
                yearName,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ...termMap.entries.map(
          (termEntry) =>
              _TermSection(termName: termEntry.key, courses: termEntry.value),
        ),
      ],
    );
  }
}

class _TermSection extends ConsumerWidget {
  const _TermSection({required this.termName, required this.courses});

  final String termName;
  final List<Course> courses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  color: AppColors.universe.textComet,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  termName,
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ...courses.map(
            (course) => CourseTile(
              course: course,
              onEdit: () async {
                await showModalBottomSheet<Course>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CourseCreateSheet(existingCourse: course),
                );
              },
              onDelete: () async {
                try {
                  await ref.read(courseRepositoryProvider).deleteCourse(course.id);
                  ref.invalidate(courseListProvider);
                  // カスケードで削除された配下のLectureをローカルにも反映する
                  await ref
                      .read(lectureControllerProvider.notifier)
                      .bootstrapLectures(forceFullPull: true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete course: $e')),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EmptyCoursesView extends StatelessWidget {
  const _EmptyCoursesView({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.school_outlined,
            size: 64,
            color: AppColors.universe.textComet,
          ),
          const SizedBox(height: 16),
          Text(
            'No courses yet',
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first course to get started',
            style: TextStyle(color: AppColors.universe.textComet),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: const Text('New Course'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// コース内授業一覧
// ---------------------------------------------------------------------------

class _CourseLectureListView extends ConsumerWidget {
  const _CourseLectureListView({required this.courseId});

  final String courseId;

  Course? _findCourse(List<Course> courses) {
    for (final c in courses) {
      if (c.id == courseId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses =
        ref.watch(courseListProvider).asData?.value ?? const <Course>[];
    final course = _findCourse(courses);
    final topicMapAsync = ref.watch(topicMapForCourseProvider(courseId));
    // Whether there's an actual map to show/open -- false while loading, on
    // error, before the pipeline has generated one, before this course
    // has any lecture_num for a map to even cover (e.g. zero lectures yet),
    // or while it's stale (a deleted/moved lecture hasn't been reconciled
    // yet -- see topic_map_reconstruct_controller.dart).
    final isTopicMapStale = topicMapAsync.maybeWhen(
      data: (topicMap) => topicMap?.isStale ?? false,
      orElse: () => false,
    );
    final canOpenTopicMap = topicMapAsync.maybeWhen(
      data: (topicMap) =>
          topicMap != null && topicMap.totalLecturesCovered > 0 && !topicMap.isStale,
      orElse: () => false,
    );
    final isReconstructingTopicMap = ref
        .watch(topicMapReconstructControllerProvider(courseId))
        .isLoading;

    // 講義日時（lecture_datetime）が新しい順にリストを表示する
    final lectures =
        (ref.watch(lectureListStreamProvider(courseId)).asData?.value ??
                const <Lecture>[])
            .toList();

    final announcement = ref
        .watch(latestAnnouncementForCourseProvider(courseId))
        .asData
        ?.value;

    if (course == null) {
      return Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: const SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.starGold),
          ),
        ),
      );
    }

    final termYearParts = [
      course.term?.attributeName,
      course.year?.attributeName,
    ].where((s) => s != null && s.isNotEmpty).toList();
    final termYearLabel = termYearParts.join(' ');

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.starGold,
          onRefresh: () => _handleRefresh(context, ref, courseId: courseId),
          child: CustomScrollView(
            slivers: [
              // 1. AppBar Area
              const SliverToBoxAdapter(
                child: CustomAppBar(showHomeButton: true),
              ),

              // 2. Main content area padding
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Row 1: Course Metadata
                    Row(
                      children: [
                        if (course.courseCode?.trim().isNotEmpty == true) ...[
                          Text(
                            course.courseCode!.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (course.professor != null)
                          Text(
                            course.professor!.attributeName.trim(),
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 14,
                            ),
                          ),
                        const Spacer(),
                        if (termYearLabel.isNotEmpty)
                          Text(
                            termYearLabel,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Row 2: Course Title & Edit Button
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              course.displayTitle,
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: () => _openEditSheet(context, course),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 3: Announcement & Detail Button
                    Row(
                      children: [
                        // Announcement Card (タップでコース内アナウンス一覧を開く)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openAnnouncementsSheet(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.universe.glassWhiteLow,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.universe.glassBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    announcement != null
                                        ? iconForAnnouncementType(
                                            announcement.type,
                                          )
                                        : Icons.campaign_outlined,
                                    color: AppColors.starGold,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      announcement?.title?.trim().isNotEmpty ==
                                              true
                                          ? announcement!.title!.trim()
                                          : (announcement?.description
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? announcement!.description!
                                                      .trim()
                                                : 'No announcements yet'),
                                      style: TextStyle(
                                        color: AppColors.universe.textStarlight,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Detailed Info Button (コースの詳細情報シートを開く)
                        GestureDetector(
                          onTap: () => _openDetailsSheet(context, course),
                          child: Container(
                            width: 64,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.universe.glassBorder,
                              ),
                            ),
                            child: const Icon(
                              Icons.dns_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Row 4: Topic Map
                    Text(
                      'Topic Map',
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isTopicMapStale
                          ? (isReconstructingTopicMap
                              ? null
                              : () => _confirmRecreateTopicMap(
                                  context,
                                  ref,
                                  courseId,
                                ))
                          : (canOpenTopicMap
                              ? () => context.push(
                                  '${AppRoutes.notesRootPath}/c/$courseId/${AppRoutes.topicMap}',
                                )
                              : null),
                      child: Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: AppColors.universe.glassWhiteLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.universe.glassBorder,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                              children: [
                                // Map Preview: the latest lecture's Lecture
                                // View, non-interactive (tapping the whole
                                // card opens the real TopicMapPage). Falls
                                // back to the decorative painter while
                                // loading, on error, before the pipeline has
                                // generated a map yet, or while stale
                                // (treated the same as "not generated yet" --
                                // opening the map is disabled either way).
                                Positioned.fill(
                                  child: isTopicMapStale
                                      ? CustomPaint(
                                          painter: _TopicMapPainter(),
                                        )
                                      : topicMapAsync.maybeWhen(
                                          data: (topicMap) {
                                            if (topicMap == null ||
                                                topicMap.totalLecturesCovered <=
                                                    0) {
                                              return CustomPaint(
                                                painter: _TopicMapPainter(),
                                              );
                                            }
                                            return ClusterMapView(
                                              data: topicMap,
                                              courseId: courseId,
                                              initialSelection:
                                                  ClusterSelection.lecture(
                                                    topicMap
                                                        .totalLecturesCovered,
                                                  ),
                                              interactive: false,
                                            );
                                          },
                                          orElse: () => CustomPaint(
                                            painter: _TopicMapPainter(),
                                          ),
                                        ),
                                ),
                                if (isTopicMapStale)
                                  // Stale: replace the whole preview with a
                                  // prominent call to action instead of the
                                  // small bottom-left hint used below --
                                  // opening the (possibly wrong) map is
                                  // disabled until the user explicitly
                                  // recreates it.
                                  Positioned.fill(
                                    child: Container(
                                      color: AppColors.universe.voidBackground
                                          .withValues(alpha: 0.55),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isReconstructingTopicMap)
                                            const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.starGold,
                                              ),
                                            )
                                          else
                                            const Icon(
                                              Icons.refresh,
                                              color: AppColors.starGold,
                                              size: 28,
                                            ),
                                          const SizedBox(height: 10),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                            ),
                                            child: Text(
                                              isReconstructingTopicMap
                                                  ? 'Recreating…'
                                                  : 'Recreate Topic Map',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: AppColors
                                                    .universe
                                                    .textStarlight,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  // Overlay Hint
                                  Positioned(
                                    bottom: 16,
                                    left: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.universe.voidBackground
                                            .withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            canOpenTopicMap
                                                ? 'Open Topic Map'
                                                : 'Not generated yet',
                                            style: TextStyle(
                                              color:
                                                  AppColors.universe.textComet,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (canOpenTopicMap) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.arrow_forward,
                                              color:
                                                  AppColors.universe.textComet,
                                              size: 14,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Row 5: Lectures Section
                    Text(
                      'Lectures',
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]),
                ),
              ),

              // Lectures List
              if (lectures.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Text(
                        'No lectures recorded yet',
                        style: TextStyle(color: AppColors.universe.textComet),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ).copyWith(bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: LectureTile(
                          lecture: lectures[index],
                          onEdit: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => LectureEditSheet(lecture: lectures[index]),
                            );
                          },
                          onDelete: () async {
                            await ref
                                .read(lectureControllerProvider.notifier)
                                .deleteLecture(
                                  lectures[index].id,
                                  courseId: lectures[index].courseId,
                                );
                          },
                        ),
                      );
                    }, childCount: lectures.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditSheet(BuildContext context, Course course) async {
    await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CourseCreateSheet(existingCourse: course),
    );
  }

  Future<void> _openAnnouncementsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CourseAnnouncementsSheet(courseId: courseId),
    );
  }

  Future<void> _openDetailsSheet(BuildContext context, Course course) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CourseDetailsSheet(course: course),
    );
  }

  Future<void> _confirmRecreateTopicMap(
    BuildContext context,
    WidgetRef ref,
    String courseId,
  ) async {
    final confirm = await showCustomDialog(
      context: context,
      title: 'Recreate Topic Map?',
      message: 'Do you want to recreate the topic map? This repairs it after recent lecture changes and may take a few seconds.',
      confirmLabel: 'Recreate',
      icon: Icons.refresh,
    );
    if (confirm != true) return;

    await ref
        .read(topicMapReconstructControllerProvider(courseId).notifier)
        .recreate();
  }
}



class _TopicMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    // Grid lines
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );

    // Concentric orbits
    canvas.drawCircle(center, 40, paint);
    canvas.drawCircle(center, 80, paint);

    final linePaint = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.3)
      ..strokeWidth = 2.0;

    final nodePaint = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    // Fake node positions
    final p1 = Offset(center.dx - 60, center.dy - 20);
    final p2 = Offset(center.dx + 30, center.dy - 60);
    final p3 = Offset(center.dx + 70, center.dy + 30);
    final p4 = Offset(center.dx - 30, center.dy + 60);

    // Connections
    canvas.drawLine(center, p1, linePaint);
    canvas.drawLine(center, p2, linePaint);
    canvas.drawLine(center, p3, linePaint);
    canvas.drawLine(center, p4, linePaint);

    // Draw nodes
    canvas.drawCircle(center, 8, nodePaint);
    canvas.drawCircle(p1, 5, nodePaint);
    canvas.drawCircle(p2, 6, nodePaint);
    canvas.drawCircle(p3, 5, nodePaint);
    canvas.drawCircle(p4, 4, nodePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> _handleRefresh(BuildContext context, WidgetRef ref, {String? courseId}) async {
  if (!await isDeviceOnline()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're offline. Showing cached data.")),
      );
    }
    return;
  }

  await ref.read(lectureControllerProvider.notifier).bootstrapLectures();
  ref.invalidate(courseListProvider);
  if (courseId != null) {
    ref.invalidate(lectureListStreamProvider(courseId));
    ref.invalidate(latestAnnouncementForCourseProvider(courseId));
  }
}
