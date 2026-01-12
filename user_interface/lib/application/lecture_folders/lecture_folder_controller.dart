import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';
import 'package:lecture_companion_ui/application/lecture_folders/lecture_folder_providers.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/application/sync/folder_sync_service.dart';
import 'dart:developer' as dev;

part 'lecture_folder_controller.g.dart';

@riverpod
class LectureFolderController extends _$LectureFolderController {
  @override
  FutureOr<void> build() {
    // UI側は Controller.state を直接使ってもいいし、
    // 既存の _loadFolders() で repoから取る方式でもOK。
    return null;
  }

  FolderSyncService _sync() {
    final db = ref.read(appDatabaseProvider);
    return FolderSyncService(db);
  }

  /// 起動時 / ページ表示時に呼ぶ：まずpullしてローカルを最新化
  Future<void> refreshFromCloud({DateTime? lastPullAt}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final sync = _sync();
      await sync.pull(lastPullAt: lastPullAt);
    });
  }

  /// create：ローカル即反映 + push
  Future<LectureFolder> createFolder({
    required String name,
    String? parentId,
    required String type,
  }) async {
    final repo = ref.read(folderRepositoryProvider);
    final folder = await repo.createFolder(name: name, parentId: parentId, type: type);

    // ネットがあればpush（失敗してもoutboxに残るのでOK）
    await _tryPush();

    return folder;
  }

  Future<void> renameFolder({
    required String folderId,
    required String newName,
  }) async {
    final repo = ref.read(folderRepositoryProvider);
    await repo.renameFolder(folderId: folderId, newName: newName);
    await _tryPush();
  }

  Future<void> setFavorite({
    required String folderId,
    required bool isFavorite,
  }) async {
    final repo = ref.read(folderRepositoryProvider);
    await repo.setFavorite(folderId: folderId, isFavorite: isFavorite);
    await _tryPush();
  }

  Future<void> deleteFolder({required String folderId}) async {
    final repo = ref.read(folderRepositoryProvider);
    await repo.softDeleteFolder(folderId: folderId);
    await _tryPush();
  }

  Future<void> _tryPush() async {
    final sync = _sync();
    try {
      await sync.pushOutbox();
      // ignore: avoid_print
      dev.log('✅ pushOutbox success');
    } catch (e, st) {
      // ignore: avoid_print
      dev.log('❌ pushOutbox failed: $e');
      // ignore: avoid_print
      dev.log(st as String);
      rethrow; // まずは原因を見るためthrowしてOK
    }
  }

  Future<void> bootstrapFolders({bool hardReset = false}) async {
    final sync = _sync();

    // 0) 任意: ローカルをSupabase正で作り直したい時だけ
    if (hardReset) {
      try {
        await sync.resetLocalToCloudBase();
      } catch (e) {
        dev.log('⚠️ reset skipped: $e');
      }
    }

    // 1) まず push（未送信を吐く）
    try {
      await sync.pushOutbox();
    } catch (e) {
      dev.log('⚠️ push skipped: $e');
    }

    // 2) 次に pull（クラウドの正を取ってくる）
    try {
      await sync.pull(lastPullAt: null); // まず全件でOK
    } catch (e) {
      dev.log('⚠️ pull skipped: $e');
    }
  }

  Future<void> bootstrapIfNeeded({Duration interval = const Duration(hours: 3)}) async {
    final nav = ref.read(navStateStoreProvider);
    final last = nav.lastFolderSyncAt;

    final now = DateTime.now().toUtc();
    final should = (last == null) || now.difference(last) >= interval;
    if (!should) return;

    try {
      await bootstrapFolders();
      await nav.setLastFolderSyncAt(now);
    } catch (_) {
      // 更新しない（次回また試す）
    }
  }

}
