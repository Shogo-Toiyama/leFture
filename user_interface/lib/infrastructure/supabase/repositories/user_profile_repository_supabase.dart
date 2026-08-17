import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/user_profile.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'user_profile_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
UserProfileRepositorySupabase userProfileRepository(Ref ref) {
  return UserProfileRepositorySupabase(ref);
}

class UserProfileRepositorySupabase {
  UserProfileRepositorySupabase(this._ref) {
    // _cachedOnboardingCompletedはこのリポジトリ(keepAlive)のインスタンス
    // が生きている間ずっと保持される。サインアウト→別アカウントでサイン
    // インをアプリを再起動せずに行うと、前のユーザーの判定結果が新しい
    // ユーザーにそのまま漏れてしまう不具合があったため、authのユーザーIDが
    // 変わるたびにキャッシュを破棄する。
    _lastUid = supabase.auth.currentUser?.id;
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final newUid = data.session?.user.id;
      if (newUid != _lastUid) {
        _cachedOnboardingCompleted = null;
        _lastUid = newUid;
      }
    });
    _ref.onDispose(() => _authSubscription.cancel());
  }

  final Ref _ref;
  String? _lastUid;
  late final StreamSubscription<AuthState> _authSubscription;

  AppDatabase get _db => _ref.read(appDatabaseProvider);
  static const _table = 'user_profiles';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// ログイン中ユーザーのプロフィールを取得してローカルDBにキャッシュ
  ///
  /// まだOutboxにpushされていないローカルの変更(例: markOnboardingCompleted
  /// が書いたばかりのonboarding_completed_at)がある場合は、サーバーの
  /// 古い値でローカルを丸ごと上書きしない。このガードが無いと、
  /// currentUserProfileProvider(Stream)がonboarding中の頻繁な画面遷移で
  /// 再生成されるたびにこの関数が呼ばれ、pushされる前のローカルの変更が
  /// 消えてしまう不具合があった。
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

    final pendingIds = await _db.getPendingOutboxEntityIds('user_profile');
    if (pendingIds.contains(uid)) {
      return profile;
    }

    // キャッシュを更新
    await _db.upsertUserProfile(
      LocalUserProfile(
        id: profile.id,
        username: profile.username,
        avatarUrl: profile.avatarUrl,
        bio: profile.bio,
        interests: profile.interests,
        futureGoals: profile.futureGoals,
        metadataJson: profile.metadata != null
            ? jsonEncode(profile.metadata)
            : null,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
      ).toCompanion(true),
    );

    return profile;
  }

  /// アバター画像を Cloudflare R2 (lefture-assets バケット) へ直接アップロードし、ストレージパスを返す
  Future<String> uploadAvatarImage(dynamic fileInput) async {
    final file = fileInput is File ? fileInput : File(fileInput.path as String);
    final fileName = file.path.split('/').last;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'png';

    final String contentType;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        contentType = 'image/jpeg';
        break;
      case 'png':
        contentType = 'image/png';
        break;
      case 'webp':
        contentType = 'image/webp';
        break;
      case 'heic':
      case 'heif':
        contentType = 'image/heic';
        break;
      case 'gif':
        contentType = 'image/gif';
        break;
      default:
        contentType = 'image/jpeg';
    }

    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not authenticated');

    // 1. R2 署名付きアップロードURLを取得
    final presignedRes = await http.post(
      Uri.parse('https://lefture-511705914929.us-west1.run.app/profile/request-avatar-upload-url'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'file_name': fileName,
        'content_type': contentType,
      }),
    ).timeout(const Duration(seconds: 20));

    if (presignedRes.statusCode != 200) {
      throw StateError('Failed to request avatar upload URL: HTTP ${presignedRes.statusCode}');
    }

    final data = jsonDecode(presignedRes.body);
    final uploadUrl = data['upload_url'] as String;
    final storagePath = data['storage_path'] as String;

    final fileBytes = await file.readAsBytes();

    // 2. Cloudflare R2 へ直接 PUT
    final putRes = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: fileBytes,
    ).timeout(const Duration(seconds: 40));

    if (putRes.statusCode != 200) {
      throw StateError('Failed to upload avatar to R2: HTTP ${putRes.statusCode}');
    }

    DevLog.add('🚀 [UserProfileRepo] Avatar photo uploaded directly to R2: $storagePath');
    return storagePath;
  }

  /// ログイン中ユーザーのプロフィールをローカルファーストで更新し、Outboxに登録してサーバー送信
  Future<UserProfile> updateProfile({
    String? username,
    String? avatarUrl,
    String? bio,
    String? interests,
    String? futureGoals,
  }) async {
    final uid = _requireUid();

    // 1. ローカルの既存データを取得
    final existing = await _db.getUserProfile(uid);

    final newUsername = username ?? existing?.username;
    final newAvatarUrl = avatarUrl ?? existing?.avatarUrl;
    final newBio = bio ?? existing?.bio;
    final newInterests = interests ?? existing?.interests;
    final newFutureGoals = futureGoals ?? existing?.futureGoals;
    final now = DateTime.now();

    // 2. ローカルDBに即座に反映 (楽観的アップデート)
    await _db.upsertUserProfile(
      LocalUserProfilesCompanion(
        id: Value(uid),
        username: Value(newUsername),
        avatarUrl: Value(newAvatarUrl),
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
      avatarUrl: newAvatarUrl,
      bio: newBio,
      interests: newInterests,
      futureGoals: newFutureGoals,
      metadata: existing?.metadataJson != null
          ? Map<String, dynamic>.from(
              jsonDecode(existing!.metadataJson!) as Map,
            )
          : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    return updatedProfile;
  }

  static const _onboardingCompletedMetadataKey = 'onboarding_completed_at';
  static const _tutorialCompletedMetadataKey = 'tutorial_completed_at';
  bool? _cachedOnboardingCompleted;
  bool? _cachedTutorialCompleted;

  /// 初回オンボーディング(プロフィール設定・Recording Language・Realtime
  /// Recording ON/OFF)を完了済みかどうか。ローカルにプロフィール行が
  /// 無い、またはmetadataにフラグが無い場合は未完了として扱う。
  ///
  /// ローカルキャッシュだけを見て判定すると、新規インストール端末で既存
  /// アカウント(既にオンボーディング済み)にサインインした直後、まだ
  /// ローカルにプロフィールが同期されていないせいで「未完了」と誤判定し、
  /// router のredirectが本来不要な /onboarding へ送ってしまう不具合があった。
  /// ローカルにフラグが見当たらない場合は、一度だけサーバーの最新値を
  /// 取得してローカルにも埋めてから、改めて判定し直す。
  Future<bool> hasCompletedOnboarding() async {
    if (_cachedOnboardingCompleted == true) {
      DevLog.add('[ProfileRepo] hasCompletedOnboarding returning in-memory true cache');
      return true;
    }

    final uid = _requireUid();
    DevLog.add('[ProfileRepo] hasCompletedOnboarding called for uid=$uid');
    var existing = await _db.getUserProfile(uid);
    // 行そのものが無いのか、行はあるがmetadataが空なのかを区別する。
    // サインアウト時のローカルデータwipeでLocalUserProfilesも消えるため、
    // サインイン直後は必ず「row MISSING」から始まり、下のサーバー取得が
    // 成功するかどうかにオンボーディング判定が完全に依存する。
    DevLog.add(
      '[ProfileRepo] local profile row: '
      '${existing == null ? "MISSING (not pulled yet, or removed by sign-out wipe)" : "present, metadataJson=${existing.metadataJson}"}',
    );
    if (existing?.metadataJson == null) {
      DevLog.add('[ProfileRepo] local metadata is null -> fetching getCurrentProfile from Supabase...');
      final startedAt = DateTime.now();
      try {
        final profile = await getCurrentProfile().timeout(const Duration(seconds: 6));
        DevLog.add(
          '[ProfileRepo] getCurrentProfile OK in '
          '${DateTime.now().difference(startedAt).inMilliseconds}ms: metadata=${profile?.metadata}',
        );
      } catch (e, st) {
        DevLog.add(
          '[ProfileRepo] getCurrentProfile FAILED after '
          '${DateTime.now().difference(startedAt).inMilliseconds}ms — the onboarding gate '
          'will fall back to "not completed" and send the user to /onboarding: $e\n$st',
        );
      }
      existing = await _db.getUserProfile(uid);
      DevLog.add('[ProfileRepo] refetched local existing metadataJson=${existing?.metadataJson}');
    }
    if (existing?.metadataJson == null) {
      DevLog.add(
        '[ProfileRepo] metadataJson still null -> returning false '
        '(=> /onboarding redirect. 既にオンボーディング済みのアカウントなら誤判定)',
      );
      return false;
    }
    final metadata = Map<String, dynamic>.from(
      jsonDecode(existing!.metadataJson!) as Map,
    );
    final completed = metadata[_onboardingCompletedMetadataKey] != null;
    DevLog.add('[ProfileRepo] onboarding_completed_at check = $completed (metadata=$metadata)');
    if (completed) {
      _cachedOnboardingCompleted = true;
    }
    return completed;
  }

  /// チュートリアル講義を完了（閲覧済み）かどうか。
  Future<bool> hasCompletedTutorial() async {
    if (_cachedTutorialCompleted == true) {
      return true;
    }

    final uid = _requireUid();
    var existing = await _db.getUserProfile(uid);
    if (existing?.metadataJson == null) {
      try {
        await getCurrentProfile().timeout(const Duration(seconds: 6));
      } catch (_) {}
      existing = await _db.getUserProfile(uid);
    }
    if (existing?.metadataJson == null) {
      return false;
    }
    try {
      final metadata = Map<String, dynamic>.from(
        jsonDecode(existing!.metadataJson!) as Map,
      );
      final completed = metadata[_tutorialCompletedMetadataKey] != null;
      if (completed) {
        _cachedTutorialCompleted = true;
      }
      return completed;
    } catch (_) {
      return false;
    }
  }

  /// オンボーディング完了をmetadataにマージして記録し、サーバーにも同期する。
  Future<void> markOnboardingCompleted() async {
    _cachedOnboardingCompleted = true;
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
    metadata[_onboardingCompletedMetadataKey] = DateTime.now()
        .toUtc()
        .toIso8601String();

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

    await _db.enqueueOutbox(
      entityType: 'user_profile',
      entityId: uid,
      op: 'update',
    );
  }

  /// チュートリアル閲覧完了をmetadataにマージして記録し、サーバーにも同期する。
  Future<void> markTutorialCompleted() async {
    _cachedTutorialCompleted = true;
    final uid = _requireUid();

    try {
      await getCurrentProfile();
    } catch (_) {}

    final existing = await _db.getUserProfile(uid);
    final metadata = existing?.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
        : <String, dynamic>{};
    
    // 既に記録済みの場合は余計なOutbox登録をスキップ
    if (metadata[_tutorialCompletedMetadataKey] != null) return;

    metadata[_tutorialCompletedMetadataKey] = DateTime.now()
        .toUtc()
        .toIso8601String();

    // 既存のオンボーディング情報やユーザープロフィール各カラムを保護しつつ、metadataJsonのみをマージ更新
    await _db.upsertUserProfile(
      LocalUserProfilesCompanion(
        id: Value(uid),
        metadataJson: Value(jsonEncode(metadata)),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _db.enqueueOutbox(
      entityType: 'user_profile',
      entityId: uid,
      op: 'update',
    );
    DevLog.add('🎓 [UserProfileRepo] Marked tutorial_completed_at and enqueued to outbox');
  }
}
