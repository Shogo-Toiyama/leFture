import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_create_sheet.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Courses',
          style: TextStyle(color: AppColors.universe.textStarlight, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: AppColors.universe.textStarlight),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.starGold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Course'),
        onPressed: () => _openCreateSheet(context, ref),
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.correctionRed)),
        ),
        data: (courses) {
          if (courses.isEmpty) {
            return _EmptyCoursesView(onCreateTap: () => _openCreateSheet(context, ref));
          }
          final grouped = _groupCourses(courses);
          return RefreshIndicator(
            color: AppColors.starGold,
            onRefresh: () async => ref.invalidate(courseListProvider),
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
      result.entries.toList()
        ..sort((a, b) {
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
        ...termMap.entries.map((termEntry) => _TermSection(
              termName: termEntry.key,
              courses: termEntry.value,
            )),
      ],
    );
  }
}

class _TermSection extends StatelessWidget {
  const _TermSection({required this.termName, required this.courses});

  final String termName;
  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: AppColors.universe.textComet, size: 16),
                const SizedBox(width: 6),
                Text(
                  termName,
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                ),
              ],
            ),
          ),
          ...courses.map((course) => _CourseTile(course: course)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: GestureDetector(
        onTap: () => context.push('${AppRoutes.notesRoot}/c/${course.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassWhiteHigh,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.school_outlined, color: AppColors.starGold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  course.displayTitle,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.universe.textComet, size: 20),
            ],
          ),
        ),
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
          Icon(Icons.school_outlined, size: 64, color: AppColors.universe.textComet),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(courseListProvider);
    final lecturesAsync = ref.watch(lectureListStreamProvider(courseId));

    final course = coursesAsync.asData?.value.where((c) => c.id == courseId).firstOrNull;
    final title = course?.displayTitle ?? 'Course';

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.universe.textStarlight),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title,
          style: TextStyle(color: AppColors.universe.textStarlight, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (course != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CourseAttributeChips(course: course),
            ),
        ],
      ),
      body: lecturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.correctionRed)),
        ),
        data: (lectures) {
          if (lectures.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none, size: 64, color: AppColors.universe.textComet),
                  const SizedBox(height: 16),
                  Text(
                    'No lectures yet',
                    style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start recording to add a lecture',
                    style: TextStyle(color: AppColors.universe.textComet),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lectures.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _LectureTile(lecture: lectures[index]),
          );
        },
      ),
    );
  }
}

class _CourseAttributeChips extends StatelessWidget {
  const _CourseAttributeChips({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (course.year != null) course.year!.attributeName,
      if (course.term != null) course.term!.attributeName,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' / '),
      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
    );
  }
}

class _LectureTile extends StatelessWidget {
  const _LectureTile({required this.lecture});

  final Lecture lecture;

  static final _dateFmt = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.notesRoot}/v/${lecture.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteHigh,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.description_outlined, color: AppColors.starGold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lecture.title?.isNotEmpty == true ? lecture.title! : 'Untitled Lecture',
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: AppColors.universe.textComet),
                      const SizedBox(width: 4),
                      Text(
                        _dateFmt.format(lecture.lectureDatetime.toLocal()),
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.universe.textComet, size: 20),
          ],
        ),
      ),
    );
  }
}
