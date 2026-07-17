import 'dart:convert';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

class UserProfileSyncService {
  final AppDatabase _db;

  UserProfileSyncService(this._db);

  static const _entityType = 'user_profile';

  Future<void> pull() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final row = await supabase
        .from('user_profiles')
        .select()
        .eq('id', uid)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(networkTimeout);

    if (row != null) {
      final pendingIds = await _db.getPendingOutboxEntityIds(_entityType);
      final isPending = pendingIds.contains(uid);

      if (!isPending) {
        await _db.upsertUserProfile(
          LocalUserProfile(
            id: uid,
            username: row['username'] as String?,
            avatarUrl: row['avatar_url'] as String?,
            bio: row['bio'] as String?,
            interests: row['interests'] as String?,
            futureGoals: row['future_goals'] as String?,
            metadataJson: row['metadata'] != null ? jsonEncode(row['metadata']) : null,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse((row['updated_at'] ?? row['created_at']) as String),
          ).toCompanion(true),
        );
        DevLog.add('📥 [UserProfileSync] Pulled user profile from cloud.');
      }
    }
  }
}
