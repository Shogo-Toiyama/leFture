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
    required String userId,
    String? courseId,
    String? title,
    DateTime? lectureDateTimeUtc,
  }) async {

    final payload = <String, dynamic>{
      'id': lectureId,
      'user_id': userId,
      'course_id': courseId,
      // 未入力ならnullのままにする（AIが生成するtitle_generatedか、
      // 表示側のフォールバックに委ねる。'Untitled Lecture'を実データとして
      // 永続化しない）
      'title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      'lecture_datetime': (lectureDateTimeUtc ?? DateTime.now().toUtc()).toIso8601String(),
    };

    await _client.from('lectures').upsert(
      payload,
      onConflict: 'id',
    );
  }
}