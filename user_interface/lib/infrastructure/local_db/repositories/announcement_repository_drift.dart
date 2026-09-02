import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'announcement_repository_drift.g.dart';

@Riverpod(keepAlive: true)
AnnouncementRepositoryDrift announcementRepositoryDrift(Ref ref) {
  return AnnouncementRepositoryDrift(ref.watch(appDatabaseProvider));
}

class AnnouncementRepositoryDrift {
  final AppDatabase _db;

  AnnouncementRepositoryDrift(this._db);

  /// 講義に紐づくアナウンスメント全件(completed_atを問わず、論理削除除外、新しい順)。
  Stream<List<Announcement>> watchAnnouncementsForLecture(String lectureId) {
    final query = _db.select(_db.localAnnouncements)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// ユーザー全体で未完了、または指定時間以降に完了したアナウンスメント一覧(新しい順、論理削除除外)。
  Stream<List<Announcement>> watchActiveAnnouncements(String userId, {DateTime? completedAfter}) {
    final query = _db.select(_db.localAnnouncements)
      ..where((t) {
        final isActiveOrRecent = completedAfter != null
            ? t.completedAt.isNull() | t.completedAt.isBiggerOrEqualValue(completedAfter)
            : t.completedAt.isNull();
        return t.userId.equals(userId) & isActiveOrRecent & t.deletedAt.isNull();
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// ユーザー全体のアナウンスメントを、状態/種類でDB側から絞り込んだ上で
  /// ページ単位(limit/offset)で取得する(1回限りの取得。ストリームではない)。
  ///
  /// ホーム画面の無限スクロール用。フィルター後の該当件数が少ない場合でも、
  /// クエリ自体が絞り込み済みのデータから返すため「読み込み済み件数の壁に
  /// 阻まれてそれ以上読み込めない」ことがない([status]='completed'等で
  /// 該当件数が少ないケースの対策)。
  Future<List<Announcement>> fetchAnnouncementsPage({
    required String userId,
    required int limit,
    required int offset,

    /// 'active' = 未完了のみ / 'completed' = 完了済みのみ / 'all' = 両方。
    required String status,
    AnnouncementType? type,
  }) async {
    final query = _db.select(_db.localAnnouncements)
      ..where((t) {
        Expression<bool> cond = t.userId.equals(userId) & t.deletedAt.isNull();
        if (status == 'active') {
          cond = cond & t.completedAt.isNull();
        } else if (status == 'completed') {
          cond = cond & t.completedAt.isNotNull();
        }
        if (type != null) {
          cond = cond & t.type.equals(type.name.toUpperCase());
        }
        return cond;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map(_toDomain).toList();
  }

  /// 指定レクチャー群(コース内の全レクチャー等)に紐づく、未完了、または指定時間以降に完了したアナウンスメント一覧。
  Stream<List<Announcement>> watchActiveAnnouncementsForLectureIds(
    List<String> lectureIds, {
    DateTime? completedAfter,
  }) {
    if (lectureIds.isEmpty) return Stream.value(const []);
    final query = _db.select(_db.localAnnouncements)
      ..where((t) {
        final isActiveOrRecent = completedAfter != null
            ? t.completedAt.isNull() | t.completedAt.isBiggerOrEqualValue(completedAfter)
            : t.completedAt.isNull();
        return t.lectureId.isIn(lectureIds) & isActiveOrRecent & t.deletedAt.isNull();
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 書き込み系で使う「自分の1行」の絞り込み条件。
  ///
  /// LocalAnnouncementsの主キーは{id, userId}の複合キーなので、idだけで
  /// 絞り込むと同じidの行が複数ユーザー分ヒットしうる(同じ端末で複数
  /// アカウントにログインした場合)。チュートリアルのアナウンスメントは
  /// 全ユーザー共通の固定id(`ann_1`等)を使うため、これが現実に起きて
  /// getSingleOrNull()が`Bad state: Too many elements`を投げていた。
  /// また、userIdを付けないUPDATEは他ユーザーの行まで巻き添えで書き換える。
  Expression<bool> Function($LocalAnnouncementsTable) _ownRow(String id, String uid) {
    return (t) => t.id.equals(id) & t.userId.equals(uid);
  }

  SimpleSelectStatement<$LocalAnnouncementsTable, LocalAnnouncement> _selectOwn(
    String id,
    String uid,
  ) {
    return _db.select(_db.localAnnouncements)..where(_ownRow(id, uid));
  }

  /// 完了/未完了を即時ローカル更新(楽観的UI)し、Outboxに登録する。
  Future<void> toggleComplete({required String id, required bool completed}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();

    await _db.transaction(() async {
      final current = await _selectOwn(id, uid).getSingleOrNull();

      await (_db.update(_db.localAnnouncements)..where(_ownRow(id, uid))).write(
        LocalAnnouncementsCompanion(
          completedAt: Value(completed ? now : null),
          updatedAt: Value(now),
        ),
      );

      // 自分の行が無い(=上のUPDATEも0件)場合と、チュートリアル講義
      // (ローカル完結)のデータはOutboxに入れない。
      if (current == null || await _db.isTutorialLecture(current.lectureId)) {
        return;
      }

      await _db.enqueueOutbox(
        entityType: 'announcement',
        entityId: id,
        op: 'update',
      );
    });
  }

  /// アナウンスメントをローカルで論理削除し、Outboxに登録する。
  Future<void> softDeleteAnnouncement({required String id}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();

    await _db.transaction(() async {
      final current = await _selectOwn(id, uid).getSingleOrNull();

      await (_db.update(_db.localAnnouncements)..where(_ownRow(id, uid))).write(
        LocalAnnouncementsCompanion(
          deletedAt: Value(now),
          syncStatus: const Value('needs_sync'),
          updatedAt: Value(now),
        ),
      );

      // 自分の行が無い(=上のUPDATEも0件)場合と、チュートリアル講義
      // (ローカル完結)のデータはOutboxに入れない。
      if (current == null || await _db.isTutorialLecture(current.lectureId)) {
        return;
      }

      await _db.enqueueOutbox(
        entityType: 'announcement',
        entityId: id,
        op: 'update', // 論理削除なのでupdate扱い
      );
    });
  }

  /// アナウンスメントのタイトル・説明・タイプを更新し、Outboxに登録する。
  Future<void> updateAnnouncement({
    required String id,
    required String title,
    required String? description,
    required AnnouncementType type,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();

    await _db.transaction(() async {
      final current = await _selectOwn(id, uid).getSingleOrNull();

      await (_db.update(_db.localAnnouncements)..where(_ownRow(id, uid))).write(
        LocalAnnouncementsCompanion(
          title: Value(title),
          description: Value(description),
          type: Value(type.name.toUpperCase()),
          syncStatus: const Value('needs_sync'),
          updatedAt: Value(now),
        ),
      );

      // 自分の行が無い(=上のUPDATEも0件)場合と、チュートリアル講義
      // (ローカル完結)のデータはOutboxに入れない。
      if (current == null || await _db.isTutorialLecture(current.lectureId)) {
        return;
      }

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
      deletedAt: row.deletedAt,
      metadata: row.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
          : null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
