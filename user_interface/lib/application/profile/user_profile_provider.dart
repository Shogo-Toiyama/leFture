import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/user_profile.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

part 'user_profile_provider.g.dart';

/// ログイン中ユーザーの user_profiles レコード
@riverpod
Stream<UserProfile?> currentUserProfile(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(null);

  final db = ref.watch(appDatabaseProvider);
  
  // 初回ロード時等にサーバーから最新を引いてくる(ローカルに書き込まれるとStreamが更新される)
  ref.read(userProfileRepositoryProvider).getCurrentProfile().catchError((_) => null);

  return db.watchUserProfile(uid).map((local) {
    if (local == null) return null;
    return UserProfile(
      id: local.id,
      username: local.username,
      avatarUrl: local.avatarUrl,
      bio: local.bio,
      interests: local.interests,
      futureGoals: local.futureGoals,
      metadata: local.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(local.metadataJson!) as Map)
          : null,
      createdAt: local.createdAt,
      updatedAt: local.updatedAt,
    );
  });
}
