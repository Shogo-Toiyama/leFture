import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

enum ActivityType {
  saved,
  likes,
  dislikes,
  announcements,
  trash,
}

enum ActivityRecordType {
  reviewCard,
  deepNote,
  funFact,
  announcement,
  lecture,
  course,
}

class ActivityRecord {
  final String id;
  final ActivityRecordType type;
  final String title;
  final String content;
  final DateTime dateTime;
  final String? lectureId;
  final String? courseId;
  final dynamic rawData;

  ActivityRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.dateTime,
    this.lectureId,
    this.courseId,
    required this.rawData,
  });
}

final allReviewCardsProvider = StreamProvider<List<LocalReviewCard>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllReviewCards(uid);
});

final allDeepNotesProvider = StreamProvider<List<LocalDeepNote>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllDeepNotes(uid);
});

final allFunFactsProvider = StreamProvider<List<LocalFunFact>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllFunFacts(uid);
});

final allAnnouncementsProvider = StreamProvider<List<LocalAnnouncement>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllAnnouncements(uid);
});

final trashLecturesProvider = StreamProvider<List<LocalLecture>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchTrashLectures(uid);
});

final trashAnnouncementsProvider = StreamProvider<List<LocalAnnouncement>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchTrashAnnouncements(uid);
});

final deletedCoursesFutureProvider = FutureProvider<List<Course>>((ref) async {
  final repo = ref.watch(courseRepositoryProvider);
  try {
    return await repo.listDeletedCourses();
  } catch (_) {
    return const [];
  }
});

final activityRecordsProvider = FutureProvider.family<List<ActivityRecord>, ActivityType>((ref, type) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const [];

  switch (type) {
    case ActivityType.saved:
      final cards = await ref.watch(allReviewCardsProvider.future);
      final notes = await ref.watch(allDeepNotesProvider.future);
      final list = <ActivityRecord>[];

      for (final row in cards) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['saved'] == true) {
          final rawContent = jsonDecode(row.cardContentJson);
          String snippet = '';
          if (rawContent is List && rawContent.isNotEmpty) {
            final first = rawContent.first;
            if (first is Map) {
              snippet = first['text']?.toString() ?? 
                  (first['items'] as List?)?.join(', ') ?? '';
            }
          }
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.reviewCard,
            title: row.title ?? 'Review Card',
            content: snippet,
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            rawData: row,
          ));
        }
      }

      for (final row in notes) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['saved'] == true) {
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.deepNote,
            title: 'Deep Note (Topic ${row.topicNumber + 1})',
            content: row.noteContents,
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            rawData: row,
          ));
        }
      }

      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return list;

    case ActivityType.likes:
    case ActivityType.dislikes:
      final isLike = type == ActivityType.likes;
      final reactionStr = isLike ? 'like' : 'dislike';

      final cards = await ref.watch(allReviewCardsProvider.future);
      final notes = await ref.watch(allDeepNotesProvider.future);
      final facts = await ref.watch(allFunFactsProvider.future);
      final list = <ActivityRecord>[];

      for (final row in cards) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['reaction'] == reactionStr) {
          final rawContent = jsonDecode(row.cardContentJson);
          String snippet = '';
          if (rawContent is List && rawContent.isNotEmpty) {
            final first = rawContent.first;
            if (first is Map) {
              snippet = first['text']?.toString() ?? 
                  (first['items'] as List?)?.join(', ') ?? '';
            }
          }
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.reviewCard,
            title: row.title ?? 'Review Card',
            content: snippet,
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            rawData: row,
          ));
        }
      }

      for (final row in notes) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['reaction'] == reactionStr) {
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.deepNote,
            title: 'Deep Note (Topic ${row.topicNumber + 1})',
            content: row.noteContents,
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            rawData: row,
          ));
        }
      }

      for (final row in facts) {
        if (row.reaction == reactionStr) {
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.funFact,
            title: row.title ?? 'Fun Fact',
            content: row.hook,
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            rawData: row,
          ));
        }
      }

      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return list;

    case ActivityType.announcements:
      final announcements = await ref.watch(allAnnouncementsProvider.future);
      final list = announcements.map((row) {
        return ActivityRecord(
          id: row.id,
          type: ActivityRecordType.announcement,
          title: row.title,
          content: row.description ?? '',
          dateTime: row.createdAt,
          lectureId: row.lectureId,
          rawData: row,
        );
      }).toList();

      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return list;

    case ActivityType.trash:
      final lectures = await ref.watch(trashLecturesProvider.future);
      final announcements = await ref.watch(trashAnnouncementsProvider.future);
      final courses = await ref.watch(deletedCoursesFutureProvider.future);
      final list = <ActivityRecord>[];

      for (final row in lectures) {
        list.add(ActivityRecord(
          id: row.id,
          type: ActivityRecordType.lecture,
          title: row.title ?? row.titleGenerated ?? 'Untitled Lecture',
          content: 'Lecture',
          dateTime: row.deletedAt ?? row.updatedAt,
          lectureId: row.id,
          courseId: row.courseId,
          rawData: row,
        ));
      }

      for (final row in announcements) {
        list.add(ActivityRecord(
          id: row.id,
          type: ActivityRecordType.announcement,
          title: row.title,
          content: row.description ?? 'Announcement',
          dateTime: row.deletedAt ?? row.updatedAt,
          lectureId: row.lectureId,
          rawData: row,
        ));
      }

      for (final course in courses) {
        list.add(ActivityRecord(
          id: course.id,
          type: ActivityRecordType.course,
          title: course.displayTitle,
          content: course.courseCode ?? 'Course',
          dateTime: course.deletedAt ?? course.updatedAt,
          courseId: course.id,
          rawData: course,
        ));
      }

      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return list;
  }
});

class TrashController {
  static Future<void> emptyTrash(WidgetRef ref) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final db = ref.read(appDatabaseProvider);
    final courseRepo = ref.read(courseRepositoryProvider);

    // 1. Supabase & Local DB deleted courses
    await courseRepo.emptyTrashCourses();

    // 2. Local DB deleted lectures & announcements
    await db.hardDeleteTrashLectures(uid);
    await db.hardDeleteTrashAnnouncements(uid);

    // 3. Supabase deleted lectures & announcements
    await supabase.from('lectures').delete().eq('user_id', uid).not('deleted_at', 'is', null);
    await supabase.from('announcements').delete().eq('user_id', uid).not('deleted_at', 'is', null);

    // 4. Force refresh deleted courses list
    ref.invalidate(deletedCoursesFutureProvider);
  }
}
