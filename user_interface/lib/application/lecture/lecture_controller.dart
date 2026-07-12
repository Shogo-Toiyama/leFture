// lib/application/lecture/lecture_controller.dart

import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/application/sync/lecture_sync_service.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart'; // jobRepository
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/review_card_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/lecture_topic_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/deep_note_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/keyword_repository_supabase.dart';
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
  Future<void> deleteLecture(String lectureId) async {
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

      // 3. 即座に同期を試みる (失敗してもOutboxにあるのでOK)
      try {
        await _sync().pushOutbox();
      } catch (e) {
        dev.log('⚠️ Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// 授業のタイトルと所属コースを更新する
  Future<void> updateLecture({
    required String lectureId,
    required String? title,
    required String? courseId,
  }) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(lectureRepositoryProvider).updateLectureTitleAndCourse(
            lectureId: lectureId,
            title: title,
            courseId: courseId,
          );

      try {
        await _sync().pushOutbox();
      } catch (e) {
        dev.log('⚠️ Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }
}