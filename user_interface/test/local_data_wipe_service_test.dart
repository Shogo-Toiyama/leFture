// サインアウト/サインイン時のローカルデータ削除は破壊的で、手で検証するには
// 2アカウント分のサインインが必要になるため、境界だけはテストで押さえておく。
//
// 実ファイルの削除はpath_providerに依存する(テスト環境ではMissingPluginException
// になる)が、[LocalDataWipeService]側がbest-effortとして握り潰す設計なので、
// DBの行に対する挙動はそのまま検証できる。
import 'dart:convert';

// `isNull`/`isNotNull` はdriftのカラム用ヘルパーとflutter_testのmatcherで名前が
// 衝突するため、driftのものは隠してmatcher側を使う。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/auth/local_data_wipe_service.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

const _me = 'user-me';
const _other = 'user-other';

Future<void> _insertLecture(AppDatabase db, String id, String userId) {
  return db
      .into(db.localLectures)
      .insert(LocalLecturesCompanion.insert(id: id, userId: userId));
}

Future<void> _insertAnnouncement(
  AppDatabase db, {
  required String id,
  required String userId,
  required String lectureId,
}) {
  return db.into(db.localAnnouncements).insert(
        LocalAnnouncementsCompanion.insert(
          id: id,
          userId: userId,
          lectureId: lectureId,
          type: 'TODO',
          title: 'title',
        ),
      );
}

Future<void> _insertAsset(
  AppDatabase db, {
  required String id,
  required String userId,
  required String lectureId,
  required String uploadStatus,
  String? localPath = '/tmp/does-not-exist.m4a',
}) {
  return db.into(db.localLectureAssets).insert(
        LocalLectureAssetsCompanion.insert(
          id: id,
          userId: userId,
          lectureId: lectureId,
          type: 'audio',
          uploadStatus: Value(uploadStatus),
          localPath: Value(localPath),
        ),
      );
}

Future<void> _insertAsrModel(AppDatabase db) {
  return db.into(db.localAsrModels).insert(
        LocalAsrModelsCompanion.insert(
          groupKey: '_whisper',
          modelId: 'whisper-small',
          engineCompatVersion: 1,
          modelVersion: 3,
          localPath: '/support/asr_models/_whisper',
          sizeBytes: 500000000,
          status: 'ready',
        ),
      );
}

void main() {
  late AppDatabase db;
  late LocalDataWipeService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = LocalDataWipeService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('countPending', () {
    test('未アップロードの録音は講義単位で数える(チャンク数ではない)', () async {
      await _insertLecture(db, 'lec-1', _me);
      // 1つの講義が3チャンクに分かれている状態。
      await _insertAsset(db, id: 'a1', userId: _me, lectureId: 'lec-1', uploadStatus: 'queued');
      await _insertAsset(db, id: 'a2', userId: _me, lectureId: 'lec-1', uploadStatus: 'failed');
      await _insertAsset(db, id: 'a3', userId: _me, lectureId: 'lec-1', uploadStatus: 'uploading');

      final pending = await service.countPending(userId: _me);

      expect(pending.pendingRecordingCount, 1);
      expect(pending.isNotEmpty, isTrue);
    });

    test('アップロード済み・他ユーザー・localPathなしは数えない', () async {
      await _insertAsset(db, id: 'a1', userId: _me, lectureId: 'lec-1', uploadStatus: 'uploaded');
      await _insertAsset(db, id: 'a2', userId: _other, lectureId: 'lec-2', uploadStatus: 'queued');
      await _insertAsset(
        db,
        id: 'a3',
        userId: _me,
        lectureId: 'lec-3',
        uploadStatus: 'queued',
        localPath: null,
      );

      final pending = await service.countPending(userId: _me);

      expect(pending.pendingRecordingCount, 0);
      expect(pending.isEmpty, isTrue);
    });

    test('Outboxの保留行を未送信の変更として数える', () async {
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'ann_1', op: 'update');
      await db.enqueueOutbox(entityType: 'lecture', entityId: 'lec-1', op: 'update');

      final pending = await service.countPending(userId: _me);

      expect(pending.pendingChangeCount, 2);
    });
  });

  group('wipeAll', () {
    test('ユーザーデータは全部消え、ASRモデルは残る', () async {
      await _insertLecture(db, 'lec-1', _me);
      await _insertAnnouncement(db, id: 'ann_1', userId: _me, lectureId: 'lec-1');
      await _insertAsset(db, id: 'a1', userId: _me, lectureId: 'lec-1', uploadStatus: 'queued');
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'ann_1', op: 'update');
      await _insertAsrModel(db);

      await service.wipeAll();

      expect(await db.select(db.localLectures).get(), isEmpty);
      expect(await db.select(db.localAnnouncements).get(), isEmpty);
      expect(await db.select(db.localLectureAssets).get(), isEmpty);
      expect(await db.select(db.localOutbox).get(), isEmpty);
      // ASRモデルは数百MBの再ダウンロードを避けるため端末に残す。
      expect(await db.select(db.localAsrModels).get(), hasLength(1));
    });

    test('プロフィールは行を残してPIIだけ消す(オンボーディング判定のフラグを守る)', () async {
      await db.upsertUserProfile(
        LocalUserProfilesCompanion.insert(
          id: _me,
          username: const Value('shogo'),
          avatarUrl: const Value('uid/avatar.jpg'),
          bio: const Value('bio'),
          interests: const Value('physics'),
          futureGoals: const Value('researcher'),
          metadataJson: Value(jsonEncode({'onboarding_completed_at': '2026-01-01T00:00:00Z'})),
        ),
      );

      await service.wipeAll();

      final profile = await db.getUserProfile(_me);
      expect(profile, isNotNull, reason: '行ごと消すとオンボーディング判定が壊れる');
      expect(profile!.username, isNull);
      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
      expect(profile.interests, isNull);
      expect(profile.futureGoals, isNull);
      expect(profile.metadataJson, contains('onboarding_completed_at'));
    });
  });

  group('reviveOutboxRetries', () {
    test('ギブアップ済み・バックオフ待ちの行を再試行対象に戻す', () async {
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'a', op: 'update');
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'b', op: 'update');
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'c', op: 'update');
      final rows = await db.select(db.localOutbox).get();
      // 1件をギブアップ、1件をバックオフ待ち(未来のnextRetryAt)にする。
      await (db.update(db.localOutbox)..where((t) => t.id.equals(rows[0].id)))
          .write(const LocalOutboxCompanion(givenUp: Value(true)));
      await (db.update(db.localOutbox)..where((t) => t.id.equals(rows[1].id))).write(
        LocalOutboxCompanion(
          nextRetryAt: Value(DateTime.now().toUtc().add(const Duration(minutes: 5))),
        ),
      );
      expect(await db.dequeuePendingOutbox(), hasLength(1));

      final revived = await service.reviveOutboxRetries();

      expect(revived, 2);
      expect(await db.dequeuePendingOutbox(), hasLength(3));
    });
  });

  group('wipeOtherUsers', () {
    test('他ユーザーの行だけ消し、自分の行とASRモデルは残す', () async {
      await _insertLecture(db, 'lec-me', _me);
      await _insertLecture(db, 'lec-other', _other);
      // チュートリアルのアナウンスは全ユーザー共通の固定idを使うため、
      // まさにこの「同じidがuserId違いで並ぶ」状態が実際に起きていた。
      await _insertAnnouncement(db, id: 'ann_1', userId: _me, lectureId: 'lec-me');
      await _insertAnnouncement(db, id: 'ann_1', userId: _other, lectureId: 'lec-other');
      await _insertAsset(db, id: 'a-other', userId: _other, lectureId: 'lec-other', uploadStatus: 'queued');
      await _insertAsrModel(db);

      await service.wipeOtherUsers(currentUserId: _me);

      final lectures = await db.select(db.localLectures).get();
      expect(lectures.map((l) => l.id), ['lec-me']);

      final announcements = await db.select(db.localAnnouncements).get();
      expect(announcements, hasLength(1));
      expect(announcements.single.userId, _me);

      expect(await db.select(db.localLectureAssets).get(), isEmpty);
      expect(await db.select(db.localAsrModels).get(), hasLength(1));
    });

    test('自分のユーザープロフィールは残す(PKがユーザーID自身のテーブル)', () async {
      await db.upsertUserProfile(LocalUserProfilesCompanion.insert(id: _me));
      await db.upsertUserProfile(LocalUserProfilesCompanion.insert(id: _other));

      await service.wipeOtherUsers(currentUserId: _me);

      final profiles = await db.select(db.localUserProfiles).get();
      expect(profiles.map((p) => p.id), [_me]);
    });

    test('残骸が無ければ何も消さない', () async {
      await _insertLecture(db, 'lec-me', _me);
      await _insertAnnouncement(db, id: 'ann_1', userId: _me, lectureId: 'lec-me');
      await db.enqueueOutbox(entityType: 'announcement', entityId: 'ann_1', op: 'update');

      await service.wipeOtherUsers(currentUserId: _me);

      expect(await db.select(db.localLectures).get(), hasLength(1));
      expect(await db.select(db.localAnnouncements).get(), hasLength(1));
      // Outboxはユーザー列を持たないため、この掃除では触らない。
      expect(await db.select(db.localOutbox).get(), hasLength(1));
    });
  });
}
