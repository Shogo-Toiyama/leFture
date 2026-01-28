// lib/application/lecture/lecture_controller.dart

import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/application/sync/lecture_sync_service.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart'; // jobRepository
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

  Future<void> bootstrapLectures({bool forceFullPull = false}) async {
    final sync = _sync();
    final nav = ref.read(navStateStoreProvider);

    try {
      await sync.pushOutbox();
    } catch (e) {
      dev.log('⚠️ Lecture push skipped: $e');
    }

    try {
      final lastSync = forceFullPull ? null : nav.lastLectureSyncAt;
      await sync.pull(lastPullAt: lastSync);
      await nav.setLastLectureSyncAt(DateTime.now().toUtc());
    } catch (e) {
      dev.log('⚠️ Lecture pull skipped: $e');
    }
  }

  Future<void> bootstrapIfNeeded({Duration interval = const Duration(minutes: 15)}) async {
    final nav = ref.read(navStateStoreProvider);
    final last = nav.lastLectureSyncAt;
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

  /// 授業を削除する
  Future<void> deleteLecture(String lectureId) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // 1. Repository経由で論理削除 + Outbox登録
      // ※ lectureRepositoryProvider は lecture_list_provider.dart で定義されているはずです
      await ref.read(lectureRepositoryProvider).softDeleteLecture(lectureId: lectureId);
      
      // 2. 即座に同期を試みる (失敗してもOutboxにあるのでOK)
      try {
        await _sync().pushOutbox();
      } catch (e) {
        dev.log('⚠️ Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }
}