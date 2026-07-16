// lib/application/lecture/lecture_controller.dart

import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/sync/lecture_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/fun_fact_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/announcement_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/keyword_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/lecture_topic_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/review_card_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/deep_note_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/topic_map_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/lecture_outbox_push_handler.dart';
import 'package:lecture_companion_ui/application/sync/fun_fact_outbox_push_handler.dart';
import 'package:lecture_companion_ui/application/sync/announcement_outbox_push_handler.dart';
import 'package:lecture_companion_ui/application/sync/review_card_outbox_push_handler.dart';
import 'package:lecture_companion_ui/application/sync/deep_note_outbox_push_handler.dart';
import 'package:lecture_companion_ui/application/maintenance/local_retention_service.dart';
import 'package:lecture_companion_ui/core/utils/connectivity_utils.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart'; // jobRepository
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/review_card_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/lecture_topic_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/deep_note_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/keyword_repository_supabase.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';

part 'lecture_controller.g.dart';

@riverpod
class LectureController extends _$LectureController {
  @override
  FutureOr<void> build() {
    return null;
  }

  LectureSyncService _sync() {
    final db = ref.read(appDatabaseProvider);
    return LectureSyncService(db);
  }

  /// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
  /// フェーズ2/3でFunFact/Announcement用のハンドラもここに追加していく。
  OutboxSyncService _outbox() {
    final db = ref.read(appDatabaseProvider);
    return OutboxSyncService(db, {
      'lecture': LectureOutboxPushHandler(),
      'fun_fact': FunFactOutboxPushHandler(),
      'announcement': AnnouncementOutboxPushHandler(),
      'review_card': ReviewCardOutboxPushHandler(),
      'deep_note': DeepNoteOutboxPushHandler(),
    });
  }

  // --- Sync / Bootstrap Logic ---

  /// UIイベント(Home画面表示・Pull-to-Refreshなど)による連続呼び出しを
  /// 間引くための、プロセス内だけのタイムスタンプ。永続化はしない —
  /// アプリがコールドスタートした直後は常にnullになるため、
  /// 起動ごとに1回は必ずbootstrapが走ることも意図している。
  DateTime? _lastBootstrapAttemptAt;

  Future<void> bootstrapLectures({bool forceFullPull = false}) async {
    // このメソッドはHome画面のuseEffect・バックグラウンド復帰・オンライン復帰など、
    // 誰も画面を見ていない/watchしていないタイミングでも呼ばれる。LectureControllerは
    // autoDisposeなので、keepAliveしないと非同期処理の途中でProviderが破棄され、
    // 以降のref.read(...)が「Cannot use the Ref...after it has been disposed」で
    // 失敗する(実際に発生していたバグ)。
    final link = ref.keepAlive();
    try {
      _lastBootstrapAttemptAt = DateTime.now().toUtc();
      final db = ref.read(appDatabaseProvider);

      // オフライン時はネットワーク処理を試みない。ここでチェックせずに
      // 各Push/Pullをawaitすると、タイムアウトが発火するまで
      // Pull-to-Refresh等の呼び出し元が長時間(プラットフォーム依存で
      // 数十秒〜数分)ブロックされてしまう不具合が実際に起きていた。
      if (await isDeviceOnline()) {
        try {
          await _outbox().pushAll();
        } catch (e, st) {
          DevLog.add('⚠️ [LectureController] Outbox push skipped: $e\n$st');
        }

        // Pull対象のエンティティ一覧。1つの失敗が他を止めないよう、
        // それぞれ独立してtry/catchする。
        final pulls = <String, Future<void> Function()>{
          'lecture': () => _sync().pull(forceFullPull: forceFullPull),
          'fun_fact': () => FunFactSyncService(db).pull(forceFullPull: forceFullPull),
          'announcement': () => AnnouncementSyncService(db).pull(forceFullPull: forceFullPull),
          'keyword': () => KeywordSyncService(db).pull(forceFullPull: forceFullPull),
          'lecture_topic': () => LectureTopicSyncService(db).pull(forceFullPull: forceFullPull),
          'review_card': () => ReviewCardSyncService(db).pull(forceFullPull: forceFullPull),
          'deep_note': () => DeepNoteSyncService(db).pull(forceFullPull: forceFullPull),
          'topic_map': () => TopicMapSyncService(db).pull(forceFullPull: forceFullPull),
        };

        for (final entry in pulls.entries) {
          try {
            await entry.value();
          } catch (e, st) {
            DevLog.add('⚠️ [LectureController] ${entry.key} pull skipped: $e\n$st');
          }
        }
      } else {
        DevLog.add('📴 [LectureController] Offline — skipping outbox push/pull.');
      }

      // ローカル保守処理(30日超の論理削除の物理削除・キャッシュ容量のLRU剥がし)。
      // Push/Pullとは独立した処理なので、失敗してもSync自体は成功として扱う。
      try {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final db = ref.read(appDatabaseProvider);
          await LocalRetentionService(db).runMaintenance(uid);
        }
      } catch (e, st) {
        DevLog.add('⚠️ [LectureController] Local retention maintenance skipped: $e\n$st');
      }
    } finally {
      link.close();
    }
  }

  /// 講義を明示的ダウンロード対象としてPin/Unpinする。Pin中はキャッシュ容量の
  /// LRU剥がし対象から除外される(将来の「ダウンロード」UIから呼ぶ想定)。
  Future<void> setLecturePinned(String lectureId, bool pinned) async {
    final db = ref.read(appDatabaseProvider);
    await db.setLecturePinned(lectureId, pinned);
  }

  Future<void> bootstrapIfNeeded({Duration interval = const Duration(minutes: 15)}) async {
    final last = _lastBootstrapAttemptAt;
    final now = DateTime.now().toUtc();

    final should = (last == null) || now.difference(last) >= interval;
    if (!should) return;

    await bootstrapLectures();
  }

  // --- Lecture Actions (Moved from ViewerController) ---

  /// 分析を開始する。[force]はStart Overなど明示的な再実行時のみtrueにする。
  Future<void> startAnalysis(String lectureId, {bool force = false}) async {
    final link = ref.keepAlive();

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(jobRepositoryProvider).startAnalysis(lectureId: lectureId, force: force);
    });

    link.close();
  }

  /// 授業を削除する。関連データ（Announcement/ReviewCard/FunFact/
  /// LectureTopic/DeepNote/Keyword）もまとめて論理削除する。
  /// 所属Courseがあった場合、そのTopic Mapのstale化(この講義のノード除去待ち)は
  /// [LectureOutboxPushHandler]がOutbox経由で送る(softDeleteLectureが積んだ
  /// 'lecture' Outbox行のpush時に、courseId/deletedAtから自動判定される)。
  /// これによりオフライン中の削除でも、Lecture本体の同期と同じリトライ保証で
  /// 確実にis_staleが立つ。実際のグラフ修復は行わない — ユーザーの
  /// 「Recreate Topic Map」操作か、Patrolのアイドルタイムアウトが後でまとめて行う
  /// (see topic_map_repository_supabase.dart / task_runners.py の設計議論)。
  Future<void> deleteLecture(String lectureId, {String? courseId}) async {
    DevLog.add('🗑️ [LectureController] deleteLecture called: $lectureId');
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // 1. Repository経由で論理削除 + Outbox登録
      // ※ lectureRepositoryProvider は lecture_list_provider.dart で定義されているはずです
      await ref.read(lectureRepositoryProvider).softDeleteLecture(lectureId: lectureId);
      DevLog.add('🗑️ [LectureController] Local soft-delete + outbox enqueue done: $lectureId');

      // 2. 関連データをカスケードで論理削除する（都度Supabaseへ直接、best-effort）
      // ※ deleteCourse と同様、現時点ではオフラインファースト化していないため、
      //   オフライン中はここが失敗する可能性がある(Lecture自体の削除はOutbox経由で
      //   後から同期されるので問題ないが、関連データの掃除は取りこぼれる)。
      try {
        await Future.wait([
          ref.read(announcementRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(reviewCardRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(funFactRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(lectureTopicRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(deepNoteRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(keywordRepositoryProvider).softDeleteForLecture(lectureId),
        ]);
      } catch (e, st) {
        DevLog.add('⚠️ [LectureController] Cascade soft-delete of related data failed: $e\n$st');
      }

      // 3. 即座に同期を試みる (失敗してもOutboxにあるのでOK)
      try {
        await _outbox().pushAll();
        DevLog.add('🗑️ [LectureController] Outbox push after delete completed: $lectureId');
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// 授業のタイトルと所属コースを更新する。[previousCourseId]と[courseId]が
  /// 異なる場合（＝Course間の移動）、旧Courseのマップからはこの講義のノードを
  /// 除去待ちに、新Courseのマップにはこの講義のトピックを追加待ちにマークする。
  /// この送信は[LectureOutboxPushHandler]がOutbox経由(バックオフ・自動リトライ付き)
  /// で行う — repository層が移動元courseIdを`pendingTopicMapStaleCourseId`に
  /// 退避しているので、オフライン中の移動でも取りこぼれない。
  Future<void> updateLecture({
    required String lectureId,
    required String? title,
    required String? courseId,
    String? previousCourseId,
    DateTime? lectureDatetime,
  }) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(lectureRepositoryProvider).updateLectureTitleAndCourse(
            lectureId: lectureId,
            title: title,
            courseId: courseId,
            previousCourseId: previousCourseId,
            lectureDatetime: lectureDatetime,
          );

      try {
        await _outbox().pushAll();
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// ローカル書き込み直後にOutboxを即座に送信したい場合に呼ぶ(例: Review Card/
  /// Deep NoteのLike・Dislike・Saveタップ)。失敗してもOutboxに残っているので、
  /// 次回のbootstrap時に自動でリトライされる。
  Future<void> pushOutboxNow() async {
    final link = ref.keepAlive();
    try {
      await _outbox().pushAll();
    } catch (e) {
      DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
    } finally {
      link.close();
    }
  }
}