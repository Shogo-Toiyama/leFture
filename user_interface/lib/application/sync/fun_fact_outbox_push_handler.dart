import 'dart:convert';

import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// FunFactはサーバー生成コンテンツで、クライアントから新規作成されることは
/// ない。ユーザーが変更できるのは`reaction`(metadata内のキー)だけなので、
/// upsertではなく`update`のみを行う(該当行がまだサーバーに存在しない
/// ケースは無いはずだが、万一無くても`update`は0件ヒットで安全に無害)。
class FunFactOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'fun_fact';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localFunFacts)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (existing == null) return;

    // チュートリアル講義配下のFunFactはローカル完結のためpushしない
    if (await db.isTutorialLecture(existing.lectureId)) return;

    final metadata = existing.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
        : <String, dynamic>{};

    if (existing.reaction != null) {
      metadata['reaction'] = existing.reaction;
    } else {
      metadata.remove('reaction');
    }

    await supabase
        .from('fun_facts')
        .update({'metadata': metadata})
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
