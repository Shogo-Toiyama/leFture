import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/user_profile.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
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

  static const _onboardingCompletedMetadataKey = 'onboarding_completed_at';

  /// 初回オンボーディング(プロフィール設定・Recording Language・Realtime
  /// Recording ON/OFF)を完了済みかどうか。ローカルにプロフィール行が
  /// 無い、またはmetadataにフラグが無い場合は未完了として扱う。
  Future<bool> hasCompletedOnboarding() async {
    final uid = _requireUid();
    final existing = await _db.getUserProfile(uid);
    if (existing?.metadataJson == null) return false;
    final metadata = Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map);
    return metadata[_onboardingCompletedMetadataKey] != null;
  }

  /// オンボーディング完了をmetadataにマージして記録し、サーバーにも同期する。
  Future<void> markOnboardingCompleted() async {
    final uid = _requireUid();

    // ローカルキャッシュがまだ空/古い状態(スキーママイグレーション直後や、
    // このデバイスでまだ一度もプロフィールを取得していない場合)でここから
    // 直接Outboxにpushしてしまうと、UserProfileOutboxPushHandlerはローカル行の
    // 値をそのままサーバーへ丸ごと`.update()`するため、まだ埋まっていない
    // username/bio/interests/futureGoals/avatarUrlをNULLでサーバー上書きして
    // しまう恐れがある。そのため、必ず先にサーバーの最新値でローカルを
    // 埋めてから、metadataだけをマージする。
    try {
      await getCurrentProfile();
    } catch (_) {
      // オフライン等で取得できない場合も、既存のローカルキャッシュのみで進める
      // (updateProfileの既存動作と同じフォールバック)。
    }

    final existing = await _db.getUserProfile(uid);
    final metadata = existing?.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
        : <String, dynamic>{};
    metadata[_onboardingCompletedMetadataKey] = DateTime.now().toUtc().toIso8601String();

    // metadataJson以外のフィールドはあえてCompanionに含めない(Value()でラップ
    // しない)。insertOnConflictUpdateは指定したカラムしか更新しないため、
    // これにより既存のusername/bio/interests/futureGoals/avatarUrlを
    // 誤って上書き・NULL化することがない。
    await _db.upsertUserProfile(
      LocalUserProfilesCompanion(
        id: Value(uid),
        metadataJson: Value(jsonEncode(metadata)),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _db.enqueueOutbox(entityType: 'user_profile', entityId: uid, op: 'update');
  }
}
