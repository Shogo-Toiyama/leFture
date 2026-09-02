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
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/application/sync/outbox_provider.dart';

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

    // まだOutboxにpushされていないローカルの変更(言語に限らず、この行の
    // どのフィールドの変更でも)がある場合、サーバーからの古い値で
    // ローカル(SharedPreferences/Riverpod状態/Driftキャッシュ)を
    // 上書きしない。UserProfileSyncService.pull()と同じ判定をここでも使う。
    final pendingIds = await _db.getPendingOutboxEntityIds('user_profile');
    final isPending = pendingIds.contains(uid);

    // クラウド上の metadata に言語設定が存在する場合はローカル(SharedPreferences等)に復元・同期する
    if (!isPending && profile.metadata != null) {
      final meta = profile.metadata!;
      final displayLang = meta[_displayLanguageMetadataKey] as String?;
      final recordingLang = meta[_recordingLanguageMetadataKey] as String?;
      if (displayLang != null && displayLang.isNotEmpty) {
        await RecordingPreferences().setDisplayLanguage(displayLang);
        try {
          _ref.read(displayLanguageControllerProvider.notifier).syncFromPreferences();
        } catch (_) {}
      }
      if (recordingLang != null && recordingLang.isNotEmpty) {
        await RecordingPreferences().setRecordingLanguage(recordingLang);
        try {
          _ref.read(recordingLanguageControllerProvider.notifier).syncFromPreferences();
        } catch (_) {}
      }
      // 端末セットアップ完了フラグはここでは立てない。この端末で実際に
      // マイク・通知・(Android)バッテリー最適化の権限が許可されているかは
      // 見ていないため、router.dart側の権限を考慮したゲートに任せる
      // (router.dartはhasCompletedOnboarding()の直後に必ずこのゲートを
      // 見るため、二重管理にはならない)。
    }

    if (isPending) {
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
  static const _tutorialCreatedMetadataKey = 'tutorial_created_at';
  static const _displayLanguageMetadataKey = 'display_language';
  static const _recordingLanguageMetadataKey = 'recording_language';
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

  /// チュートリアル講義を完了（閲覧済み）した日時。未完了ならnull。
  Future<DateTime?> tutorialCompletedAt() async {
    final uid = _requireUid();
    var existing = await _db.getUserProfile(uid);
    if (existing?.metadataJson == null) {
      try {
        await getCurrentProfile().timeout(const Duration(seconds: 6));
      } catch (_) {}
      existing = await _db.getUserProfile(uid);
    }
    if (existing?.metadataJson == null) {
      return null;
    }
    try {
      final metadata = Map<String, dynamic>.from(
        jsonDecode(existing!.metadataJson!) as Map,
      );
      final raw = metadata[_tutorialCompletedMetadataKey] as String?;
      if (raw == null) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        _cachedTutorialCompleted = true;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// チュートリアル講義を完了（閲覧済み）かどうか。
  Future<bool> hasCompletedTutorial() async {
    if (_cachedTutorialCompleted == true) {
      return true;
    }
    return (await tutorialCompletedAt()) != null;
  }

  /// チュートリアル講義が「本当はいつ作られたか」を表す、ユーザーごとに
  /// 一度だけ確定する日時。値がまだ無ければ今この瞬間を採番し、metadataへ
  /// 記録してサーバーにも同期したうえで返す(初回シード時に一度だけ書き込みが
  /// 走り、以降は既存値を読むだけになる)。
  ///
  /// ★ tutorial_completed_at(閲覧完了日時)とは別の概念。チュートリアル講義
  /// 自体はローカル限定でSupabaseに書き込まれないため、サインアウトの
  /// ローカルデータwipeでlocal_lectures行ごと消えてしまう。再シード時に
  /// 「今日できたばかりの新規講義」に見えてしまわないよう、真の作成日を
  /// このmetadata(user_profiles、サインアウトでも生き残る)に固定し、
  /// TutorialLectureSeedServiceはここから読んだ日時を講義のcreatedAtとして
  /// 使う。
  Future<DateTime> ensureTutorialCreatedAt() async {
    final uid = _requireUid();
    var existing = await _db.getUserProfile(uid);
    if (existing?.metadataJson == null) {
      // ローカルにまだ何も無い(新規端末での初回サインイン等)場合のみ、
      // 他デバイスで既に確定済みの値が無いかサーバーに確認する。
      try {
        await getCurrentProfile().timeout(const Duration(seconds: 6));
      } catch (_) {}
      existing = await _db.getUserProfile(uid);
    }

    final metadata = existing?.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
        : <String, dynamic>{};

    final raw = metadata[_tutorialCreatedMetadataKey] as String?;
    final parsed = raw != null ? DateTime.tryParse(raw) : null;
    if (parsed != null) return parsed;

    final now = DateTime.now().toUtc();
    metadata[_tutorialCreatedMetadataKey] = now.toIso8601String();

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
    DevLog.add('🎓 [UserProfileRepo] Recorded tutorial_created_at=$now and enqueued to outbox');

    return now;
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
    metadata[_displayLanguageMetadataKey] = RecordingPreferences().getDisplayLanguage();
    metadata[_recordingLanguageMetadataKey] = RecordingPreferences().getRecordingLanguage();

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
    await _pushOutboxImmediately();
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

  /// 表示言語（display_language: 'ja', 'en'等）をuser_profilesのmetadataに保存・マージし、
  /// サーバー(Supabase user_profilesテーブル & Supabase Auth user_metadata)へ同期する。
  Future<void> setDisplayLanguage(String languageCode) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final existing = await _db.getUserProfile(uid);
    final metadata = existing?.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
        : <String, dynamic>{};

    if (metadata[_displayLanguageMetadataKey] == languageCode) return;

    metadata[_displayLanguageMetadataKey] = languageCode;
    metadata[_recordingLanguageMetadataKey] ??= RecordingPreferences().getRecordingLanguage();

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

    DevLog.add('🌐 [UserProfileRepo] Saved display_language=$languageCode to metadata and enqueued to outbox');

    // UIをブロックしないよう、ネットワーク通信(Auth更新 & Outbox Push)は非同期バックグラウンドで実行
    unawaited(_syncAuthUserMetadataAndPush(
      displayLanguage: languageCode,
      recordingLanguage: metadata[_recordingLanguageMetadataKey] as String?,
    ));
  }

  /// 録音言語（recording_language: 'ja', 'en'等）をuser_profilesのmetadataに保存・マージし、
  /// サーバー(Supabase user_profilesテーブル & Supabase Auth user_metadata)へ同期する。
  Future<void> setRecordingLanguage(String languageCode) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // 「自動判定」はFlutter内部では具体的な文字列コード(kAutoDetectLanguageCode)
    // として扱っているが、lectures.recording_languageをはじめバックエンド側は
    // 「未設定(null)なら自動判定」という規約で統一されている。ここ(サーバーへの
    // 書き込み境界)で正規化しておかないと、このmetadataだけ'auto'という
    // 生の文字列が入り、規約が食い違ってしまう。
    final normalized = languageCode == kAutoDetectLanguageCode ? null : languageCode;

    final existing = await _db.getUserProfile(uid);
    final metadata = existing?.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(existing!.metadataJson!) as Map)
        : <String, dynamic>{};

    if (metadata[_recordingLanguageMetadataKey] == normalized &&
        metadata[_displayLanguageMetadataKey] != null) {
      return;
    }

    metadata[_recordingLanguageMetadataKey] = normalized;
    metadata[_displayLanguageMetadataKey] ??= RecordingPreferences().getDisplayLanguage();

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

    DevLog.add('🌐 [UserProfileRepo] Saved recording_language=$normalized (raw="$languageCode") to metadata and enqueued to outbox');

    // UIをブロックしないよう、ネットワーク通信(Auth更新 & Outbox Push)は非同期バックグラウンドで実行
    unawaited(_syncAuthUserMetadataAndPush(
      recordingLanguage: normalized,
      displayLanguage: metadata[_displayLanguageMetadataKey] as String?,
    ));
  }

  Future<void> _syncAuthUserMetadataAndPush({
    String? displayLanguage,
    String? recordingLanguage,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (displayLanguage != null) data['display_language'] = displayLanguage;
      if (recordingLanguage != null) data['recording_language'] = recordingLanguage;

      if (data.isNotEmpty) {
        await supabase.auth.updateUser(
          UserAttributes(data: data),
        );
      }
    } catch (e) {
      DevLog.add('⚠️ [UserProfileRepo] Failed to update Auth user_metadata: $e');
    }

    await _pushOutboxImmediately();
  }

  Future<void> _pushOutboxImmediately() async {
    try {
      // ★ 以前はここでuser_profileハンドラだけを持つ「狭い」OutboxSyncService
      // をその場で作っていた。pushAll()はentityTypeを問わず保留中の全Outbox行
      // (lecture_moment等)をまとめて処理してしまうため、そのタイミングで他の
      // 種別の行が残っていると「ハンドラが無い」失敗として記録され、実際には
      // ハンドラが存在する本来のpush(outboxSyncServiceProvider経由)より前に
      // 誤った失敗履歴を残してしまっていた。共通providerを使い、常に全ハンドラ
      // が揃った状態でpushする。
      await _ref.read(outboxSyncServiceProvider).pushAll();
    } catch (e) {
      DevLog.add('⚠️ [UserProfileRepo] Failed to push user_profile outbox immediately: $e');
    }
  }
}

