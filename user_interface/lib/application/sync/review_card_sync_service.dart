import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// ReviewCardのPull(Supabase→ローカルDB)専用サービス。ユーザーによる書き込みが
/// 無い読み取り専用キャッシュなので、Outbox/Push側の対応は不要。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。
class ReviewCardSyncService {
  final AppDatabase _db;

  ReviewCardSyncService(this._db);

  static const _entityType = 'review_card';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localReviewCards)
          ..where((t) => t.userId.equals(uid) & t.deletedAt.isNull()))
        .get()
        .then((rows) => rows.length);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    var query = supabase.from('review_cards').select().eq('user_id', uid);
    if (effectiveLastPullAt != null) {
      final skewBuffer = effectiveLastPullAt.subtract(const Duration(minutes: 5));
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
        final cardContent = json['card_content'];
        return LocalReviewCardsCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          lectureId: Value(json['lecture_id'] as String),
          topicNumber: Value((json['topic_number'] as num?)?.toInt() ?? 0),
          cardContentJson: Value(jsonEncode(cardContent ?? const [])),
          cardType: Value(json['card_type'] as String? ?? ''),
          title: Value(json['title'] as String?),
          heroEmoji: Value(json['hero_emoji'] as String?),
          metadataJson: Value(
            json['metadata'] != null ? jsonEncode(json['metadata']) : null,
          ),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
          ),
          lastSyncedAt: Value(now),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localReviewCards, companions);
      });

      DevLog.add('📥 [ReviewCardSync] Pulled ${companions.length} review card(s) from cloud.');
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
