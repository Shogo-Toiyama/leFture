import 'dart:convert';
import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

class UserProfileOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'user_profile';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await db.getUserProfile(entityId);
    if (existing == null) return;

    final metadata = existing.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
        : <String, dynamic>{};

    // このpushはローカル行の値でサーバーの全カラムを`.update()`する。そのため、
    // ローカル行が「metadataだけ入った、まだサーバーの値で埋まっていない行」
    // (サインアウト時のスクラブ直後や、getCurrentProfileに失敗したまま
    // markOnboardingCompletedが走った場合)をそのまま送ると、サーバー側の
    // username/bio/interests/future_goals/avatar_urlをNULLで消してしまう。
    //
    // 個人情報のカラムが1つも埋まっていない行は「信用できないキャッシュ」と
    // 判断し、metadata(オンボーディング/チュートリアル完了フラグ)だけを送る。
    // updateProfile()は `username ?? existing?.username` 方式で「nullは変更なし」
    // として扱うため、ユーザー操作でこの4つを同時にNULLにすることはできない。
    // つまりこの判定が正規の編集を取りこぼすことはない。
    final hasNoPersonalFields = existing.username == null &&
        existing.avatarUrl == null &&
        existing.bio == null &&
        existing.interests == null &&
        existing.futureGoals == null;

    final payload = <String, dynamic>{
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (!hasNoPersonalFields) ...{
        'username': existing.username,
        'avatar_url': existing.avatarUrl,
        'bio': existing.bio,
        'interests': existing.interests,
        'future_goals': existing.futureGoals,
      },
    };

    if (hasNoPersonalFields) {
      DevLog.add(
        '🛡️ [UserProfilePush] Local profile row has no personal fields yet — '
        'pushing metadata only so the server copy is not nulled (entity=$entityId)',
      );
    }

    await supabase
        .from('user_profiles')
        .update(payload)
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
