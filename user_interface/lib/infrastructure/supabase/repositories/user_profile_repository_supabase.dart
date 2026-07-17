import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/user_profile.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_profile_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
UserProfileRepositorySupabase userProfileRepository(Ref ref) {
  return UserProfileRepositorySupabase(ref);
}

class UserProfileRepositorySupabase {
  UserProfileRepositorySupabase(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(appDatabaseProvider);
  static const _table = 'user_profiles';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// ログイン中ユーザーのプロフィールを取得してローカルDBにキャッシュ
  Future<UserProfile?> getCurrentProfile() async {
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select()
        .eq('id', uid)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (row == null) return null;

    final profile = UserProfile.fromMap(row);

    // キャッシュを更新
    await _db.upsertUserProfile(
      LocalUserProfile(
        id: profile.id,
        username: profile.username,
        avatarUrl: profile.avatarUrl,
        bio: profile.bio,
        interests: profile.interests,
        futureGoals: profile.futureGoals,
        metadataJson: profile.metadata != null ? jsonEncode(profile.metadata) : null,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
      ).toCompanion(true),
    );

    return profile;
  }

  /// ログイン中ユーザーのプロフィールをローカルファーストで更新し、Outboxに登録してサーバー送信
  Future<UserProfile> updateProfile({
    String? username,
    String? bio,
    String? interests,
    String? futureGoals,
  }) async {
    final uid = _requireUid();

    // 1. ローカルの既存データを取得
    final existing = await _db.getUserProfile(uid);
    
    final newUsername = username ?? existing?.username;
    final newBio = bio ?? existing?.bio;
    final newInterests = interests ?? existing?.interests;
    final newFutureGoals = futureGoals ?? existing?.futureGoals;
    final now = DateTime.now();

    // 2. ローカルDBに即座に反映 (楽観的アップデート)
    await _db.upsertUserProfile(
      LocalUserProfilesCompanion(
        id: Value(uid),
        username: Value(newUsername),
        bio: Value(newBio),
        interests: Value(newInterests),
        futureGoals: Value(newFutureGoals),
        updatedAt: Value(now),
      ),
    );

    // 3. Outboxに登録して同期キューに入れる
    await _db.enqueueOutbox(
      entityType: 'user_profile',
      entityId: uid,
      op: 'update',
    );

    // ドメインモデルを返す
    final updatedProfile = UserProfile(
      id: uid,
      username: newUsername,
      avatarUrl: existing?.avatarUrl,
      bio: newBio,
      interests: newInterests,
      futureGoals: newFutureGoals,
      metadata: existing?.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
          : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    return updatedProfile;
  }
}
