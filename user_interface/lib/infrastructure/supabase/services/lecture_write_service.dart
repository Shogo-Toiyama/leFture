import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';

part 'lecture_write_service.g.dart';

@Riverpod(keepAlive: true)
LectureWriteService lectureWriteService(Ref ref) {
  return LectureWriteService(supabase);
}

class LectureWriteService {
  LectureWriteService(this._client);
  final SupabaseClient _client;

  Future<void> upsertLecture({
    required String lectureId,
    required String ownerId,
    String? folderId,
    String? title,
    DateTime? lectureDateTimeUtc,
    bool isDeleted = false,
  }) async {

    final payload = <String, dynamic>{
      'id': lectureId,
      'owner_id': ownerId,
      'folder_id': folderId,
      'title': (title != null && title.trim().isNotEmpty) ? title.trim() : 'Untitled Lecture',
      'lecture_datetime': (lectureDateTimeUtc ?? DateTime.now().toUtc()).toIso8601String(),
      'is_deleted': isDeleted,
    };

    await _client.from('lectures').upsert(
      payload,
      onConflict: 'id',
    );
  }

  Future<void> upsertAudioAsset({
    required String assetId,
    required String lectureId,
    required String ownerId,
    required String bucket,
    required String path,
  }) async {
    final payload = <String, dynamic>{
      'id': assetId,
      'lecture_id': lectureId,
      'owner_id': ownerId,
      'type': 'audio',
      'storage_bucket': bucket,
      'storage_path': path,
    };

    // retry/duplicateに強いように upsert
    await _client.from('lecture_assets').upsert(
      payload,
      onConflict: 'id',
    );
  }
}