import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageUploadService {
  StorageUploadService(this._client);
  final SupabaseClient _client;

  // あなたの bucket 名に合わせてここだけ統一
  String get audioBucket => 'lecture_assets';

  Future<String> uploadAudioFile({
    required String userId,
    required String lectureId,
    required String localPath,
    required String fileName,
  }) async {
    final remotePath = '$userId/$lectureId/audio/$fileName';
    final file = File(localPath);

    await _client.storage.from(audioBucket).upload(
          remotePath,
          file,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'audio/mp4',
          ),
        );

    return remotePath;
  }
}
