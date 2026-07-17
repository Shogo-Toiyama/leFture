import 'dart:convert';
import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

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

    await supabase
        .from('user_profiles')
        .update({
          'username': existing.username,
          'avatar_url': existing.avatarUrl,
          'bio': existing.bio,
          'interests': existing.interests,
          'future_goals': existing.futureGoals,
          'metadata': metadata,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
