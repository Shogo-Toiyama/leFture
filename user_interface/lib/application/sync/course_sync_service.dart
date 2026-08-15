import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// コースのPull(Supabase→ローカルDB)専用のサービス。コースの作成/更新/削除
/// (Push側)は、他エンティティと違いOutbox経由のオフライン対応をしておらず、
/// [CourseRepositorySupabase]がオンライン時に直接書き込む設計のまま
/// (作成/更新/削除の頻度が低く、都度オンラインを要求しても実用上大きな
/// 支障が無いため)。ただしPull(読み取りキャッシュ)はここでLectureと
/// 同じ形に揃えることで、通信不良時にコース一覧が消えて見える問題を防ぐ。
class CourseSyncService {
  final AppDatabase _db;

  CourseSyncService(this._db);

  static const _entityType = 'course';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull =
        forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    var query = supabase.from('courses').select().eq('user_id', uid);

    if (!needsFullPull && cursor.lastPulledAt != null) {
      final skewBuffer = cursor.lastPulledAt!.subtract(
        const Duration(minutes: 5),
      );
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }
        final metadata = json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null;
        return LocalCoursesCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          courseTitle: Value(
            json['course_title'] as String? ?? 'Untitled Course',
          ),
          courseCode: Value(json['course_code'] as String?),
          summary: Value(json['summary'] as String?),
          schoolId: Value(json['school_id'] as String?),
          yearId: Value(json['year_id'] as String?),
          termId: Value(json['term_id'] as String?),
          subjectId: Value(json['subject_id'] as String?),
          // DBのカラム名は "professor"(course_attributesへのFK)
          professorId: Value(json['professor'] as String?),
          metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null
                ? null
                : DateTime.parse(json['deleted_at'] as String),
          ),
          syncStatus: const Value('synced'),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localCourses, companions);
      });

      DevLog.add(
        '📥 [CourseSync] Pulled ${companions.length} course(s) from cloud.',
      );
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
  }
}
