// lib/application/lecture/lecture_controller.dart

import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/sync/lecture_sync_service.dart';
import 'package:lecture_companion_ui/application/maintenance/local_retention_service.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart'; // jobRepository
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/review_card_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/lecture_topic_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/deep_note_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/keyword_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/topic_map_repository_supabase.dart';
import 'dart:developer' as dev;

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

  // --- Sync / Bootstrap Logic ---

  /// UIイベント(Home画面表示・Pull-to-Refreshなど)による連続呼び出しを
  /// 間引くための、プロセス内だけのタイムスタンプ。永続化はしない —
  /// アプリがコールドスタートした直後は常にnullになるため、
  /// 起動ごとに1回は必ずbootstrapが走ることも意図している。
  DateTime? _lastBootstrapAttemptAt;

  Future<void> bootstrapLectures({bool forceFullPull = false}) async {
    _lastBootstrapAttemptAt = DateTime.now().toUtc();
    final sync = _sync();

    try {
      await sync.pushOutbox();
    } catch (e, st) {
      dev.log('⚠️ Lecture push skipped: $e', error: e, stackTrace: st);
    }

    try {
      await sync.pull(forceFullPull: forceFullPull);
    } catch (e, st) {
      dev.log('⚠️ Lecture pull skipped: $e', error: e, stackTrace: st);
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
      dev.log('⚠️ Local retention maintenance skipped: $e', error: e, stackTrace: st);
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

  /// 分析を開始する
  Future<void> startAnalysis(String lectureId) async {
    final link = ref.keepAlive();

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(jobRepositoryProvider).startAnalysis(lectureId: lectureId);
    });

    link.close();
  }

  /// 授業を削除する。関連データ（Announcement/ReviewCard/FunFact/
  /// LectureTopic/DeepNote/Keyword）もまとめて論理削除する。
  /// [courseId]が分かる場合は、そのCourseのTopic Mapもこの講義のノード除去待ち
  /// (stale)としてマークする。実際のグラフ修復は行わない — ユーザーの
  /// 「Recreate Topic Map」操作か、Patrolのアイドルタイムアウトが後でまとめて行う
  /// (see topic_map_repository_supabase.dart / task_runners.py の設計議論)。
  Future<void> deleteLecture(String lectureId, {String? courseId}) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // 1. Repository経由で論理削除 + Outbox登録
      // ※ lectureRepositoryProvider は lecture_list_provider.dart で定義されているはずです
      await ref.read(lectureRepositoryProvider).softDeleteLecture(lectureId: lectureId);

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
        dev.log('⚠️ Cascade soft-delete of related data failed: $e', error: e, stackTrace: st);
      }

      // 2.5 Topic Mapをstaleとしてマーク（LLMは呼ばない軽量な記録だけ、best-effort）
      if (courseId != null) {
        try {
          await ref.read(topicMapRepositoryProvider).markStale(
                courseId: courseId,
                lectureId: lectureId,
                action: 'remove',
              );
        } catch (e, st) {
          dev.log('⚠️ Failed to mark topic map stale: $e', error: e, stackTrace: st);
        }
      }

      // 3. 即座に同期を試みる (失敗してもOutboxにあるのでOK)
      try {
        await _sync().pushOutbox();
      } catch (e) {
        dev.log('⚠️ Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// 授業のタイトルと所属コースを更新する。[previousCourseId]と[courseId]が
  /// 異なる場合（＝Course間の移動）、旧Courseのマップからはこの講義のノードを
  /// 除去待ちに、新Courseのマップにはこの講義のトピックを追加待ちにマークする
  /// (どちらもLLMは呼ばない軽量な記録のみ、best-effort)。
  Future<void> updateLecture({
    required String lectureId,
    required String? title,
    required String? courseId,
    String? previousCourseId,
  }) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(lectureRepositoryProvider).updateLectureTitleAndCourse(
            lectureId: lectureId,
            title: title,
            courseId: courseId,
          );

      if (courseId != previousCourseId) {
        final topicMapRepo = ref.read(topicMapRepositoryProvider);
        try {
          await Future.wait([
            if (previousCourseId != null)
              topicMapRepo.markStale(
                courseId: previousCourseId,
                lectureId: lectureId,
                action: 'remove',
              ),
            if (courseId != null)
              topicMapRepo.markStale(
                courseId: courseId,
                lectureId: lectureId,
                action: 'add',
              ),
          ]);
        } catch (e, st) {
          dev.log('⚠️ Failed to mark topic map(s) stale after course move: $e', error: e, stackTrace: st);
        }
      }

      try {
        await _sync().pushOutbox();
      } catch (e) {
        dev.log('⚠️ Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }
}