import 'dart:developer' as dev;
import 'dart:io';

import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';

/// ローカルDB/ローカルファイルの保存領域を健全に保つための保守処理。
///
/// 1. Supabase側はdeleted_atから30日後に物理削除する方針のため、クライアント
///    側でも独立して同じ基準でローカルの論理削除済みデータを物理削除する。
///    サーバーの物理削除は「行が消えるだけ」でupdated_atを更新するイベントでは
///    ないため、差分Pullでは検出できず、これをやらないとローカルにゴミが
///    永久に残り続けてしまう。
/// 2. R2からキャッシュしたファイル(トランスクリプト・トピック画像等)の合計
///    サイズが[defaultCacheBudgetBytes]を超えたら、Pin(明示的ダウンロード)
///    されていない講義のうち最後にアクセスした時刻が古いものから順にキャッシュ
///    だけを剥がす。講義本体の軽量メタデータ(LocalLecturesの行自体)は
///    一覧に表示され続けられるよう残す。
class LocalRetentionService {
  LocalRetentionService(this._db);

  final AppDatabase _db;

  static const Duration softDeleteRetention = Duration(days: 30);

  /// 厳密な上限ではなく目安。多少超えても実害はないため、判定タイミングを
  /// 増やしてまで厳密化する必要はない。
  static const int defaultCacheBudgetBytes = 1 * 1024 * 1024 * 1024; // 1GB

  Future<void> runMaintenance(String userId) async {
    try {
      await purgeExpiredSoftDeletes(userId);
    } catch (e, st) {
      dev.log('⚠️ purgeExpiredSoftDeletes failed: $e', error: e, stackTrace: st);
    }

    try {
      await enforceCacheBudget(userId);
    } catch (e, st) {
      dev.log('⚠️ enforceCacheBudget failed: $e', error: e, stackTrace: st);
    }
  }

  /// deleted_atから[softDeleteRetention](30日)を過ぎ、かつサーバーへの反映が
  /// 完了している(syncStatus == 'synced')講義をローカルから完全に削除する。
  /// 未送信の削除(needs_sync)はOutbox送信と競合しないよう対象外にする。
  Future<void> purgeExpiredSoftDeletes(String userId) async {
    final threshold = DateTime.now().toUtc().subtract(softDeleteRetention);
    final expired = await _db.getExpiredSoftDeletedLectures(
      userId: userId,
      olderThan: threshold,
    );
    if (expired.isEmpty) return;

    for (final lecture in expired) {
      await _deleteAllLocalFilesForLecture(userId: userId, lectureId: lecture.id);
      await _db.hardDeleteLectureCascade(lecture.id);
    }
    dev.log('🗑️ [Retention] Purged ${expired.length} expired soft-deleted lecture(s).');
  }

  /// Pinされていない講義のキャッシュ合計サイズが[budgetBytes]を超えたら、
  /// 最後にアクセスした時刻が古い講義から順にキャッシュファイル+キャッシュ済み
  /// コンテンツ行を削除する(講義本体の行は残す)。Pin済み講義の容量はこの
  /// 判定から除外する(ユーザーが明示的にダウンロードした分は制限を無視する)。
  Future<void> enforceCacheBudget(
    String userId, {
    int budgetBytes = defaultCacheBudgetBytes,
  }) async {
    final pinnedIds = (await _db.getPinnedLectureIds(userId)).toSet();

    final entries = await _db.getAllCacheEntries(userId);
    final nonPinnedEntries = entries.where((e) => !pinnedIds.contains(e.lectureId));

    final sizeByLecture = <String, int>{};
    for (final entry in nonPinnedEntries) {
      sizeByLecture.update(
        entry.lectureId,
        (v) => v + entry.sizeBytes,
        ifAbsent: () => entry.sizeBytes,
      );
    }
    if (sizeByLecture.isEmpty) return;

    var totalBytes = sizeByLecture.values.fold<int>(0, (a, b) => a + b);
    if (totalBytes <= budgetBytes) return;

    final candidates = await _db.getLecturesByIds(userId, sizeByLecture.keys.toList());
    // 最後にアクセスした時刻が古い順(未アクセスはcreatedAtで代用)にLRU評価
    candidates.sort((a, b) {
      final aAt = a.lastAccessedAt ?? a.createdAt;
      final bAt = b.lastAccessedAt ?? b.createdAt;
      return aAt.compareTo(bAt);
    });

    var evictedCount = 0;
    for (final lecture in candidates) {
      if (totalBytes <= budgetBytes) break;
      final freed = sizeByLecture[lecture.id] ?? 0;
      if (freed == 0) continue;

      await _deleteCacheFilesOnDisk(userId: userId, lectureId: lecture.id);
      await _db.deleteCacheEntriesForLecture(userId: userId, lectureId: lecture.id);
      totalBytes -= freed;
      evictedCount++;
    }

    if (evictedCount > 0) {
      final remainingMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      dev.log('🧹 [Retention] Evicted cache for $evictedCount lecture(s), remaining ≈ ${remainingMb}MB.');
    }
  }

  Future<void> _deleteCacheFilesOnDisk({required String userId, required String lectureId}) async {
    final entries = await _db.getCacheEntriesForLecture(userId, lectureId);
    for (final entry in entries) {
      try {
        final file = File(entry.localFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        dev.log('⚠️ [Retention] Failed to delete cache file ${entry.localFilePath}: $e');
      }
    }
  }

  /// 講義を完全に消す前に、R2キャッシュファイルと、まだ端末に残っている
  /// 録音済み音声(通常はアップロード成功時に削除済みのはず)を掃除する。
  Future<void> _deleteAllLocalFilesForLecture({
    required String userId,
    required String lectureId,
  }) async {
    await _deleteCacheFilesOnDisk(userId: userId, lectureId: lectureId);

    final assets = await _db.getAssetsForLecture(lectureId);
    for (final asset in assets) {
      final localPath = asset.localPath;
      if (localPath == null) continue;
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        dev.log('⚠️ [Retention] Failed to delete asset file $localPath: $e');
      }
    }
  }
}
