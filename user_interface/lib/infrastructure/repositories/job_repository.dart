// lib/infrastructure/repositories/job_repository.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/processing_jobs.dart';
import '../../domain/entities/processing_task.dart';

class JobRepository {
  final SupabaseClient _supabase;

  JobRepository(this._supabase);

  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  Stream<ProcessingJobs?> watchJob(String lectureId) {
    // dev.log('👀 Start watching Job for: $lectureId');

    return _supabase
        .from('processing_jobs')
        .stream(primaryKey: ['id'])
        .eq('lecture_id', lectureId)
        .map((maps) {
          if (maps.isEmpty) {
            // dev.log('📭 Job list is empty');
            return null;
          }

          // 日付で並べ替え
          maps.sort((a, b) {
             final aTime = a['created_at'] as String? ?? '';
             final bTime = b['created_at'] as String? ?? '';
             return bTime.compareTo(aTime);
          });

          final latestMap = maps.first;
          // dev.log('📄 Processing map: $latestMap'); // ★ここ重要：生データを見る

          try {
            // ここで変換エラーが起きているはず！
            return ProcessingJobs.fromJson(latestMap);
          } catch (e, s) {
            dev.log('🚨 Parse Error: $e'); // エラー内容を表示
            dev.log('Stack trace: $s');
            return null; // エラーなら一旦nullを返してアプリを落とさない
          }
        });
  }

  /// 指定ジョブに紐づく全タスク（進捗・エラー表示用）をRealtime監視する
  Stream<List<ProcessingTask>> watchTasksForJob(String jobId) {
    return _supabase
        .from('processing_tasks')
        .stream(primaryKey: ['id'])
        .eq('job_id', jobId)
        .map((rows) => rows.map((e) => ProcessingTask.fromMap(e)).toList());
  }

  /// 分析を開始する（Cloud RunのDAGパイプラインを起動）。
  /// アップロード完了後の自動発火(upload_manager.dart)と同じエンドポイントを叩く。
  /// expected_chunksは、既にアップロード済みのチャンク数(lecture_transcripts)から
  /// 算出する — この呼び出しはNotStartedView（音声アップロード済み）からのみ行われるため。
  Future<void> startAnalysis({required String lectureId}) async {
    final expectedChunks = await _supabase
        .from('lecture_transcripts')
        .count()
        .eq('lecture_id', lectureId);

    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot start analysis.');
    }

    final response = await http.post(
      Uri.parse('$_cloudRunBaseUrl/start-analysis'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({'lecture_id': lectureId, 'expected_chunks': expectedChunks}),
    );

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Failed to start analysis (${response.statusCode}): ${response.body}');
    }
  }

  /// FAILEDのまま自動リトライを使い切って止まっているタスク1件だけをやり直す。
  /// ジョブ全体は作り直さないので、既に完了した他のタスクは無駄にならない。
  Future<void> retryTask({required String taskId}) async {
    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot retry task.');
    }

    final response = await http.post(
      Uri.parse('$_cloudRunBaseUrl/retry-task'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({'task_id': taskId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to retry task (${response.statusCode}): ${response.body}');
    }
  }
}
