import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'announcement_repository_drift.g.dart';

@Riverpod(keepAlive: true)
AnnouncementRepositoryDrift announcementRepositoryDrift(Ref ref) {
  return AnnouncementRepositoryDrift(ref.watch(appDatabaseProvider));
}

class AnnouncementRepositoryDrift {
  final AppDatabase _db;

  AnnouncementRepositoryDrift(this._db);

  /// 講義に紐づくアナウンスメント全件(completed_atを問わず、論理削除除外、発生順)。
  Stream<List<Announcement>> watchAnnouncementsForLecture(String lectureId) {
    final query = _db.select(_db.localAnnouncements)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// ユーザー全体で未完了のアナウンスメント一覧(新しい順、論理削除除外)。
  Stream<List<Announcement>> watchActiveAnnouncements(String userId) {
    final query = _db.select(_db.localAnnouncements)
      ..where((t) =>
          t.userId.equals(userId) & t.completedAt.isNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 指定レクチャー群(コース内の全レクチャー等)に紐づく、未完了のアナウンスメント一覧。
  Stream<List<Announcement>> watchActiveAnnouncementsForLectureIds(List<String> lectureIds) {
    if (lectureIds.isEmpty) return Stream.value(const []);
    final query = _db.select(_db.localAnnouncements)
      ..where((t) =>
          t.lectureId.isIn(lectureIds) & t.completedAt.isNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 完了/未完了を即時ローカル更新(楽観的UI)し、Outboxに登録する。
  Future<void> toggleComplete({required String id, required bool completed}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.localAnnouncements)..where((t) => t.id.equals(id))).write(
        LocalAnnouncementsCompanion(
          completedAt: Value(completed ? now : null),
          updatedAt: Value(now),
        ),
      );

      await _db.enqueueOutbox(
        entityType: 'announcement',
        entityId: id,
        op: 'update',
      );
    });
  }

  Announcement _toDomain(LocalAnnouncement row) {
    return Announcement(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      type: announcementTypeFromString(row.type),
      title: row.title,
      description: row.description,
      location: row.location,
      startSid: row.startSid?.toString(),
      endSid: row.endSid?.toString(),
      relatedTopicTitle: row.relatedTopicTitle,
      datetimeParameters: row.datetimeParametersJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.datetimeParametersJson!) as Map)
          : null,
      completedAt: row.completedAt,
      metadata: row.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
          : null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
