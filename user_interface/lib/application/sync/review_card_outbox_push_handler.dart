import 'dart:convert';

import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// ReviewCardはサーバー生成コンテンツで、クライアントから新規作成されることは
/// ない。ユーザーが変更できるのは`metadata`(reaction/saved)だけなので、
/// upsertではなく`update`のみを行う。
class ReviewCardOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'review_card';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localReviewCards)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (existing == null) return;

    // チュートリアル講義配下の復習カードはローカル完結のためpushしない
    if (await db.isTutorialLecture(existing.lectureId)) return;

    final metadata = existing.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
        : <String, dynamic>{};

    await supabase
        .from('review_cards')
        .update({'metadata': metadata})
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
