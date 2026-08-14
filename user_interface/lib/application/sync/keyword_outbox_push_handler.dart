import 'dart:convert';

import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// Keywordはサーバー生成コンテンツ。ユーザーが変更できるのは`metadata`(saved等)だけなので、
/// Supabaseへ`metadata`カラムのupdateのみを行う。
class KeywordOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'keyword';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localKeywords)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (existing == null) return;

    // チュートリアル講義配下のキーワードはローカル完結のためpushしない
    if (await db.isTutorialLecture(existing.lectureId)) return;

    final metadata = existing.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
        : <String, dynamic>{};

    await supabase
        .from('keywords')
        .update({
          'metadata': metadata,
          'keyword': existing.keyword,
          'definition': existing.definition,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
