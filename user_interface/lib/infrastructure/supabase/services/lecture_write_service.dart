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
    String? recordingLanguage,
    String? displayLanguage,
  }) async {

    final payload = <String, dynamic>{
      'id': lectureId,
      'user_id': userId,
      'course_id': courseId,
      // 未入力ならnullのままにする（AIが生成するtitle_generatedか、
      // 表示側のフォールバックに委ねる。'Untitled Lecture'を実データとして
      // 永続化しない）
      'title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      // 未入力（または過去の互換性等でnull）の場合は現在時刻にフォールバックする
      'lecture_datetime': (lectureDateTimeUtc?.toUtc() ?? DateTime.now().toUtc()).toIso8601String(),
      // ★ 以前はここに無く、ローカルDBには保存されているのにSupabase側の
      // lectures行には初回登録時点では一切反映されない(その後ソフト削除等で
      // LectureOutboxPushHandlerが走った時だけ"ついで"に同期される)というバグが
      // あったため、初回登録の時点で確実に送るようにする。
      'recording_language': recordingLanguage,
      'display_language': displayLanguage,
    };

    await _client.from('lectures').upsert(
      payload,
      onConflict: 'id',
    );
  }
}