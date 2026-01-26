import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/application/sync/lecture_sync_service.dart'; // さっき作ったファイル
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

  /// ---------------------------------------------------------
  /// Bootstrap: Push -> Pull の順で同期を実行
  /// ---------------------------------------------------------
  Future<void> bootstrapLectures({bool forceFullPull = false}) async {
    final sync = _sync();
    final nav = ref.read(navStateStoreProvider);

    // 1) Push (ローカルの未送信分を送る)
    try {
      await sync.pushOutbox();
    } catch (e) {
      dev.log('⚠️ Lecture push skipped: $e');
      // Push失敗してもPullは試みる
    }

    // 2) Pull (クラウドの最新を取る)
    try {
      // 前回同期時刻を取得 (forceFullPullならnullにして全件取得)
      final lastSync = forceFullPull ? null : nav.lastLectureSyncAt;
      
      await sync.pull(lastPullAt: lastSync);
      
      // 成功したら同期時刻を更新
      await nav.setLastLectureSyncAt(DateTime.now().toUtc());
      
    } catch (e) {
      dev.log('⚠️ Lecture pull skipped: $e');
    }
  }

  /// ---------------------------------------------------------
  /// 必要に応じて同期を実行 (インターバル制御)
  /// UIの useEffect などから呼ぶ用
  /// ---------------------------------------------------------
  Future<void> bootstrapIfNeeded({Duration interval = const Duration(minutes: 15)}) async {
    final nav = ref.read(navStateStoreProvider);
    final last = nav.lastLectureSyncAt;

    final now = DateTime.now().toUtc();
    
    // 初回、または前回からインターバル以上経過していたら実行
    final should = (last == null) || now.difference(last) >= interval;
    
    if (!should) {
      dev.log('Skipping lecture sync (last synced at $last)');
      return;
    }

    await bootstrapLectures();
  }
}