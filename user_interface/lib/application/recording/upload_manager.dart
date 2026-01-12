import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../infrastructure/supabase/supabase_client.dart';
import '../../infrastructure/supabase/services/lecture_write_service.dart';
import '../../infrastructure/supabase/services/storage_upload_service.dart';
import '../../core/services/audio_record/pending_upload_store.dart';

class UploadManager {
  UploadManager({
    required PendingUploadStore store,
    required StorageUploadService uploader,
    required LectureWriteService lectureWriter,
  })  : _store = store,
        _uploader = uploader,
        _lectureWriter = lectureWriter {
    _sub = Connectivity().onConnectivityChanged.listen((event) {
      // event が List<ConnectivityResult> のバージョンもある
      if (!_isOffline(event)) {
        tryProcessQueue();
      }
    });

    // 起動直後にも一回だけ
    scheduleMicrotask(tryProcessQueue);
  }

  final PendingUploadStore _store;
  final StorageUploadService _uploader;
  final LectureWriteService _lectureWriter;

  StreamSubscription? _sub;
  bool _running = false;

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  bool _isOffline(dynamic results) {
    if (results is List<ConnectivityResult>) {
      return results.contains(ConnectivityResult.none);
    }
    if (results is ConnectivityResult) {
      return results == ConnectivityResult.none;
    }
    return false;
  }

  Future<void> tryProcessQueue() async {
    if (_running) return;
    _running = true;

    try {
      final results = await Connectivity().checkConnectivity();
      if (_isOffline(results)) return;

      final jobs = await _store.load();
      if (jobs.isEmpty) return;

      for (final job in jobs) {
        // 念のため auth が居ない時はスキップ
        final user = supabase.auth.currentUser;
        if (user == null) return;

        try {
          // lecture row は存在してる前提だけど、無い可能性もあるので最低限 upsert
          await _lectureWriter.upsertLecture(
            lectureId: job.lectureId,
            ownerId: job.userId,
            folderId: null,
            title: null,
            lectureDateTimeUtc: DateTime.now().toUtc(),
          );

          final remotePath = await _uploader.uploadAudioFile(
            userId: job.userId,
            lectureId: job.lectureId,
            localPath: job.localPath,
            fileName: job.fileName,
          );

          // ここが大事：キュー経由で成功しても lecture_assets を必ず作る
          await _lectureWriter.upsertAudioAsset(
            assetId: job.id, // job.id を assetId として扱う
            lectureId: job.lectureId,
            ownerId: job.userId,
            bucket: _uploader.audioBucket,
            path: remotePath,
          );

          await _store.remove(job.id);
        } catch (e) {
          final updated = job.copyWith(attempts: job.attempts + 1);
          await _store.update(updated);
        }
      }
    } finally {
      _running = false;
    }
  }
}
