// lib/infrastructure/repositories/job_repository.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/network_constants.dart';
import '../../domain/entities/processing_jobs.dart';
import '../../domain/entities/processing_task.dart';

class JobRepository {
  final SupabaseClient _supabase;

  JobRepository(this._supabase);

  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  // 分析進捗の表示は12ステップ中どこまで進んだかという粗い比率のみで、
  // 秒単位の追従は不要(講義全体の分析は数分〜十数分規模)。以前はSupabase
  // Realtimeの.stream()に依存していたが、どのテーブルもRealtimeが
  // 有効化されておらず実質「画面を開いた瞬間の1回分」しか更新を受け取れて
  // いなかったため、ポーリングに切り替える。
  static const _pollInterval = Duration(seconds: 3);

  /// 指定講義の最新ジョブをポーリング監視する。ジョブがCOMPLETEDになったら
  /// 最後の値をyieldしてポーリングを終了する(それ以上変化しないため)。
  Stream<ProcessingJobs?> watchJob(String lectureId) async* {
    while (true) {
      ProcessingJobs? job;
      try {
        final maps = await _supabase
            .from('processing_jobs')
            .select()
            .eq('lecture_id', lectureId)
            .timeout(networkTimeout);

        if (maps.isNotEmpty) {
          // 日付で並べ替え
          final sorted = [...maps]..sort((a, b) {
            final aTime = a['created_at'] as String? ?? '';
            final bTime = b['created_at'] as String? ?? '';
            return bTime.compareTo(aTime);
          });

          try {
            job = ProcessingJobs.fromJson(sorted.first);
          } catch (e, s) {
            dev.log('🚨 Parse Error: $e'); // エラー内容を表示
            dev.log('Stack trace: $s');
          }
        }
      } catch (e, s) {
        // 通信エラー等。落とさずに次回のポーリングでリトライする。
        dev.log('🚨 watchJob poll error: $e');
        dev.log('Stack trace: $s');
      }

      yield job;

      if (job != null && job.status == 'COMPLETED') break;
      await Future.delayed(_pollInterval);
    }
  }

  /// 指定ジョブに紐づく全タスク（進捗・エラー表示用）をポーリング監視する。
  /// 全タスクが終端状態(COMPLETED/FAILED/CANCELLED)になったらポーリングを
  /// 終了する。
  Stream<List<ProcessingTask>> watchTasksForJob(String jobId) async* {
    const terminalStatuses = {'COMPLETED', 'FAILED', 'CANCELLED'};

    while (true) {
      List<ProcessingTask> tasks = const [];
      try {
        final rows = await _supabase
            .from('processing_tasks')
            .select()
            .eq('job_id', jobId)
            .timeout(networkTimeout);
        tasks = rows.map((e) => ProcessingTask.fromMap(e)).toList();
      } catch (e, s) {
        // 通信エラー等。落とさずに次回のポーリングでリトライする。
        dev.log('🚨 watchTasksForJob poll error: $e');
        dev.log('Stack trace: $s');
      }

      yield tasks;

      final allTerminal =
          tasks.isNotEmpty && tasks.every((t) => terminalStatuses.contains(t.status));
      if (allTerminal) break;
      await Future.delayed(_pollInterval);
    }
  }

  /// 分析を開始する（Cloud RunのDAGパイプラインを起動）。
  /// アップロード完了後の自動発火(upload_manager.dart)と同じエンドポイントを叩く。
  /// expected_chunksは、既にアップロード済みのチャンク数(lecture_transcripts)から
  /// 算出する — この呼び出しはNotStartedView（音声アップロード済み）からのみ行われるため。
  /// [force] は「Start Over」など、ユーザーが明示的に再実行を選んだ場合のみ
  /// trueにする。既存の未完了Jobをキャンセルして新しいJobを作り直す。
  /// false(既定)の場合、既に未完了Jobがあればサーバー側が新規作成せず既存
  /// Jobを返す(冪等)。
  Future<void> startAnalysis({required String lectureId, bool force = false}) async {
    final expectedChunks = await _supabase
        .from('lecture_transcripts')
        .count()
        .eq('lecture_id', lectureId)
        .timeout(networkTimeout);

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
      body: jsonEncode({
        'lecture_id': lectureId,
        'expected_chunks': expectedChunks,
        'force': force,
      }),
    ).timeout(networkTimeout);

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Failed to start analysis (${response.statusCode}): ${response.body}');
    }
  }

  /// 指定タスクをやり直す(FAILED/COMPLETEDどちらの状態からでも呼べる)。
  /// バックエンド側でそのタスクに依存する後続タスクも連鎖的にPENDINGへ戻す
  /// (カスケードリトライ)。ジョブ全体は作り直さないので、影響範囲外の
  /// 完了済みタスクは無駄にならない。
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
    ).timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to retry task (${response.statusCode}): ${response.body}');
    }
  }
}
