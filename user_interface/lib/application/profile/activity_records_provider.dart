import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lefture/core/utils/text_preview.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

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
  keyword,
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

final allKeywordsProvider = StreamProvider<List<LocalKeyword>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllKeywords(uid);
});

final allLectureTopicsProvider = StreamProvider<List<LocalLectureTopic>>((ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchAllLectureTopics(uid);
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
      final keywords = await ref.watch(allKeywordsProvider.future);
      final topics = await ref.watch(allLectureTopicsProvider.future);
      final db = ref.watch(appDatabaseProvider);
      final lectures = await db.watchAllLectures(uid).first;
      final lectureCourseMap = {for (final l in lectures) l.id: l.courseId};
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
            content: plainTextPreview(snippet),
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            courseId: lectureCourseMap[row.lectureId],
            rawData: row,
          ));
        }
      }

      for (final row in notes) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['saved'] == true) {
          final topic = topics.cast<LocalLectureTopic?>().firstWhere(
                (t) => t?.lectureId == row.lectureId && t?.topicIndex == row.topicNumber,
                orElse: () => null,
              );
          final title = topic?.topicTitle.trim().isNotEmpty == true
              ? topic!.topicTitle
              : 'Deep Note (Topic ${row.topicNumber})';

          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.deepNote,
            title: title,
            content: plainTextPreview(row.noteContents),
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            courseId: lectureCourseMap[row.lectureId],
            rawData: row,
          ));
        }
      }

      for (final row in keywords) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['saved'] == true) {
          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.keyword,
            title: row.keyword.trim().isNotEmpty ? row.keyword.trim() : 'Keyword',
            content: plainTextPreview(row.definition),
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            courseId: lectureCourseMap[row.lectureId],
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
      final topics = await ref.watch(allLectureTopicsProvider.future);
      final facts = await ref.watch(allFunFactsProvider.future);
      final db = ref.watch(appDatabaseProvider);
      final lectures = await db.watchAllLectures(uid).first;
      final lectureCourseMap = {for (final l in lectures) l.id: l.courseId};
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
            content: plainTextPreview(snippet),
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            courseId: lectureCourseMap[row.lectureId],
            rawData: row,
          ));
        }
      }

      for (final row in notes) {
        final metadata = row.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
            : null;
        if (metadata?['reaction'] == reactionStr) {
          final topic = topics.cast<LocalLectureTopic?>().firstWhere(
                (t) => t?.lectureId == row.lectureId && t?.topicIndex == row.topicNumber,
                orElse: () => null,
              );
          final title = topic?.topicTitle.trim().isNotEmpty == true
              ? topic!.topicTitle
              : 'Deep Note (Topic ${row.topicNumber})';

          list.add(ActivityRecord(
            id: row.id,
            type: ActivityRecordType.deepNote,
            title: title,
            content: plainTextPreview(row.noteContents),
            dateTime: row.updatedAt,
            lectureId: row.lectureId,
            courseId: lectureCourseMap[row.lectureId],
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
            content: plainTextPreview(row.hook),
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
        final displayTitle = (row.title?.trim().isNotEmpty == true)
            ? row.title!.trim()
            : ((row.titleGenerated?.trim().isNotEmpty == true)
                ? row.titleGenerated!.trim()
                : 'Untitled Lecture');
        list.add(ActivityRecord(
          id: row.id,
          type: ActivityRecordType.lecture,
          title: displayTitle,
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
  static Future<void> restoreItem(WidgetRef ref, ActivityRecord record) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final db = ref.read(appDatabaseProvider);
    final courseRepo = ref.read(courseRepositoryProvider);

    if (record.type == ActivityRecordType.course) {
      await courseRepo.restoreCourse(record.id);
    } else if (record.type == ActivityRecordType.lecture) {
      await (db.update(db.localLectures)..where((t) => t.id.equals(record.id))).write(
        LocalLecturesCompanion(
          deletedAt: const Value(null),
          syncStatus: const Value('needs_sync'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (!await db.isTutorialLecture(record.id)) {
        await db.enqueueOutbox(entityType: 'lecture', entityId: record.id, op: 'update');
      }
    } else if (record.type == ActivityRecordType.announcement) {
      await (db.update(db.localAnnouncements)..where((t) => t.id.equals(record.id))).write(
        LocalAnnouncementsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final ann = await (db.select(db.localAnnouncements)..where((t) => t.id.equals(record.id))).getSingleOrNull();
      if (ann == null || !await db.isTutorialLecture(ann.lectureId)) {
        await db.enqueueOutbox(entityType: 'announcement', entityId: record.id, op: 'update');
      }
    }

    ref.invalidate(deletedCoursesFutureProvider);
    ref.invalidate(activityRecordsProvider(ActivityType.trash));
  }

  static const _backendBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  static String _requireJwt() {
    final jwt = supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot delete trash item.');
    }
    return jwt;
  }

  /// 講義・コースの完全削除は、子テーブル(keywords/lecture_transcripts/
  /// processing_jobs/R2ファイル等)まで含めてバックエンドの _hard_delete_lecture/
  /// _hard_delete_course が一元管理する。Flutter 側では再実装しない。
  /// バックエンドでの削除が成功した後にのみローカルを削除する。
  static Future<void> deleteSingleItem(WidgetRef ref, ActivityRecord record) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final db = ref.read(appDatabaseProvider);

    if (record.type == ActivityRecordType.course) {
      final jwt = _requireJwt();
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/courses/${record.id}/hard-delete'),
        headers: {'Authorization': 'Bearer $jwt'},
      ).timeout(const Duration(seconds: 30));
      // 404 = バックエンド側では既に削除済み(前回の呼び出しが実は成功していた/
      // 二重タップ等)。これはエラーではなく「削除完了」として扱い、ローカルの
      // 掃除だけ行う。404以外の失敗だけを本当の失敗として例外送出する。
      if (response.statusCode != 200 && response.statusCode != 404) {
        throw Exception('Failed to delete course (${response.statusCode}): ${response.body}');
      }
      await db.hardDeleteCourseCascade(record.id);

    } else if (record.type == ActivityRecordType.lecture) {
      final jwt = _requireJwt();
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/lectures/${record.id}/hard-delete'),
        headers: {'Authorization': 'Bearer $jwt'},
      ).timeout(const Duration(seconds: 30));
      // 404 = バックエンド側では既に削除済み。同上の理由でエラー扱いにしない。
      if (response.statusCode != 200 && response.statusCode != 404) {
        throw Exception('Failed to delete lecture (${response.statusCode}): ${response.body}');
      }
      await db.hardDeleteLectureCascade(record.id);

    } else if (record.type == ActivityRecordType.announcement) {
      // 子テーブルを持たない単純な行なので、これまで通り直接 Supabase を叩く。
      await supabase
          .from('announcements')
          .delete()
          .eq('id', record.id)
          .eq('user_id', uid);
      await (db.delete(db.localAnnouncements)..where((t) => t.id.equals(record.id))).go();
    }

    ref.invalidate(deletedCoursesFutureProvider);
    ref.invalidate(activityRecordsProvider(ActivityType.trash));
  }

  /// ゴミ箱を空にする。バックエンドの /trash/empty が、コース→講義の順で
  /// 1件ずつ完全削除し、失敗した id を返す。失敗した項目はローカルの
  /// ゴミ箱にも残し(次回再試行できるように)、成功した項目だけローカルからも消す。
  static Future<EmptyTrashResult> emptyTrash(WidgetRef ref) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const EmptyTrashResult(coursesDeleted: 0, coursesFailed: [], lecturesDeleted: 0, lecturesFailed: []);

    final jwt = _requireJwt();
    final response = await http.post(
      Uri.parse('$_backendBaseUrl/trash/empty'),
      headers: {'Authorization': 'Bearer $jwt'},
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Failed to empty trash (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final coursesFailed = (body['courses_failed'] as List).cast<String>();
    final lecturesFailed = (body['lectures_failed'] as List).cast<String>();

    final db = ref.read(appDatabaseProvider);
    final courseRepo = ref.read(courseRepositoryProvider);

    // 失敗したコース配下の講義は、コース自体が消えていないのでローカルにも残す。
    final trashLectures = await db.watchTrashLectures(uid).first;
    final skipLectureIds = {
      ...lecturesFailed,
      for (final lecture in trashLectures)
        if (lecture.courseId != null && coursesFailed.contains(lecture.courseId)) lecture.id,
    };
    for (final lecture in trashLectures) {
      if (!skipLectureIds.contains(lecture.id)) {
        await db.hardDeleteLectureCascade(lecture.id);
      }
    }

    final deletedCourses = await courseRepo.listDeletedCourses();
    for (final course in deletedCourses) {
      if (!coursesFailed.contains(course.id)) {
        await db.hardDeleteCourseCascade(course.id);
      }
    }

    await db.hardDeleteTrashAnnouncements(uid);

    ref.invalidate(deletedCoursesFutureProvider);
    ref.invalidate(activityRecordsProvider(ActivityType.trash));

    return EmptyTrashResult(
      coursesDeleted: (body['courses_deleted'] as num).toInt(),
      coursesFailed: coursesFailed,
      lecturesDeleted: (body['lectures_deleted'] as num).toInt(),
      lecturesFailed: lecturesFailed,
    );
  }
}

class EmptyTrashResult {
  const EmptyTrashResult({
    required this.coursesDeleted,
    required this.coursesFailed,
    required this.lecturesDeleted,
    required this.lecturesFailed,
  });

  final int coursesDeleted;
  final List<String> coursesFailed;
  final int lecturesDeleted;
  final List<String> lecturesFailed;

  bool get hasFailures => coursesFailed.isNotEmpty || lecturesFailed.isNotEmpty;
}
