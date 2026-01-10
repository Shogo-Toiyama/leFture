import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageUploadService {
  StorageUploadService(this._client);

  final SupabaseClient _client;

  // TODO: あなたの実bucket名に合わせて変更
  static const String audioBucket = 'lecture_assets';

  Future<String> uploadAudioFile({
    required String userId,
    required String lectureId,
    required String localPath,
    required String fileName,
  }) async {
    final remotePath = '$userId/$lectureId/audio/$fileName';
    final fullPath = await _client.storage.from(audioBucket).upload(
      remotePath,
      File(localPath),
      fileOptions: const FileOptions(
        upsert: false,
        contentType: 'audio/mp4',
      ),
    );
    return fullPath;
  }
}
