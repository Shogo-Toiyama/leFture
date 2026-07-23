import 'dart:convert';

import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

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

    final metadata = existing.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
        : <String, dynamic>{};

    await supabase
        .from('keywords')
        .update({'metadata': metadata})
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
