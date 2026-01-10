import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/audio_record/pending_upload_store.dart';
import '../../infrastructure/supabase/services/storage_upload_service.dart';

final pendingUploadStoreProvider = Provider<PendingUploadStore>((ref) {
  return PendingUploadStore();
});

final storageUploadServiceProvider = Provider<StorageUploadService>((ref) {
  // 既存: lib/infrastructure/supabase/supabase_client.dart で作っている想定
  // supabase_flutter を使っているなら Supabase.instance.client でOK
  return StorageUploadService(Supabase.instance.client);
});

final uploadManagerProvider = Provider<UploadManager>((ref) {
  final mgr = UploadManager(
    ref.read(pendingUploadStoreProvider),
    ref.read(storageUploadServiceProvider),
  );

  // Providerが生きている間だけ監視
  mgr.start();
  ref.onDispose(mgr.dispose);
  return mgr;
});

class UploadManager {
  UploadManager(this._store, this._uploader);

  final PendingUploadStore _store;
  final StorageUploadService _uploader;

  StreamSubscription? _sub;
  bool _running = false;

  void start() {
    // 起動直後にも一回試す
    _tryProcessQueue();

    _sub = Connectivity().onConnectivityChanged.listen((_) {
      _tryProcessQueue();
    });
  }

  void dispose() {
    _sub?.cancel();
  }

  Future<void> _tryProcessQueue() async {
    if (_running) return;
    _running = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) return;

      final jobs = await _store.load();
      for (final job in jobs) {
        try {
          await _uploader.uploadAudioFile(
            userId: job.userId,
            lectureId: job.lectureId,
            localPath: job.localPath,
            fileName: job.fileName,
          );
          await _store.removeById(job.id);
        } catch (_) {
          // 失敗したら attempts を増やして一旦止める（無限連打防止）
          await _store.update(job.copyWith(attempts: job.attempts + 1));
          break;
        }
      }
    } finally {
      _running = false;
    }
  }
}
