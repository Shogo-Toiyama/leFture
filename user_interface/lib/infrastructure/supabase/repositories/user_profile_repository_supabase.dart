import 'package:lecture_companion_ui/domain/entities/user_profile.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_profile_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
UserProfileRepositorySupabase userProfileRepository(Ref ref) {
  return UserProfileRepositorySupabase();
}

class UserProfileRepositorySupabase {
  static const _table = 'user_profiles';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// ログイン中ユーザーのプロフィールを取得
  Future<UserProfile?> getCurrentProfile() async {
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select()
        .eq('id', uid)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (row == null) return null;
    return UserProfile.fromMap(row);
  }

  /// ログイン中ユーザーのプロフィールを更新（サインアップ時にトリガーで
  /// 行自体は作成済みなので、ここでは常にupdate）
  Future<UserProfile> updateProfile({
    String? username,
    String? profile,
    String? interests,
    String? futureGoals,
  }) async {
    final uid = _requireUid();

    final updated = await supabase
        .from(_table)
        .update({
          if (username != null) 'username': username,
          if (profile != null) 'profile': profile,
          if (interests != null) 'interests': interests,
          if (futureGoals != null) 'future_goals': futureGoals,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', uid)
        .select()
        .single();

    return UserProfile.fromMap(updated);
  }
}
