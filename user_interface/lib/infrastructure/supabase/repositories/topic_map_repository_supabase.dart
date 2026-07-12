import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/topic_map_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
TopicMapRepositorySupabase topicMapRepository(Ref ref) {
  return TopicMapRepositorySupabase();
}

class TopicMapRepositorySupabase {
  static const _table = 'topic_maps';

  // job_repository.dart と同じ値。共通定数化されていないのは既存の踏襲。
  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  /// The course's topic map, or null if the pipeline hasn't generated one
  /// yet. One row per course is assumed; if that ever changes, the
  /// `updated_at` ordering here picks the most recently generated map.
  Future<TopicMapData?> getForCourse(String courseId) async {
    final row = await supabase
        .from(_table)
        .select('map, is_stale')
        .eq('course_id', courseId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final mapJson = row?['map'] as Map<String, dynamic>?;
    if (mapJson == null) return null;

    return TopicMapData.fromJson(mapJson, isStale: row?['is_stale'] as bool? ?? false);
  }

  String get _jwt {
    final jwt = supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot reach the topic map service.');
    }
    return jwt;
  }

  /// Lectureの削除、またはCourse間の移動が起きた瞬間に呼ぶ。LLMは呼ばず、
  /// バックエンド側でpending_removals/pending_additionsに記録して
  /// is_staleを立てるだけの軽量な呼び出し(即座に返る)。
  /// action: "remove"(このCourseからlectureIdのノードを除去待ちにする) または
  ///         "add"(lectureIdのトピックをこのCourseへの追加待ちにする)。
  /// 失敗しても呼び出し元(LectureController)はbest-effortとして扱う想定。
  Future<void> markStale({
    required String courseId,
    required String lectureId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$_cloudRunBaseUrl/topic-map/mark-stale'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode({
        'course_id': courseId,
        'lecture_id': lectureId,
        'action': action,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark topic map stale (${response.statusCode}): ${response.body}');
    }
  }

  /// 「Recreate Topic Map」から呼ぶ。pending_removals/pending_additionsを
  /// まとめて消化し、LLMによる修復を同期的に実行する(数秒かかりうる)。
  Future<void> reconstruct({required String courseId}) async {
    final response = await http.post(
      Uri.parse('$_cloudRunBaseUrl/topic-map/reconstruct'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode({'course_id': courseId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to reconstruct topic map (${response.statusCode}): ${response.body}');
    }
  }
}
