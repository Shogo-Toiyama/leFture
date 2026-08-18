// lib/infrastructure/repositories/job_repository.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/network_constants.dart';
import '../../domain/entities/processing_jobs.dart';
import '../../domain/entities/processing_task.dart';
import '../../domain/exceptions/insufficient_credits_exception.dart';

class JobRepository {
  final SupabaseClient _supabase;

  JobRepository(this._supabase);

  static const _cloudRunBaseUrl =
      'https://lefture-511705914929.us-west1.run.app';

  // 分析進捗の表示は12ステップ中どこまで進んだかという粗い比率のみで、
  // 秒単位の追従は不要(講義全体の分析は数分〜十数分規模)。以前はSupabase
  // Realtimeの.stream()に依存していたが、どのテーブルもRealtimeが
  // 有効化されておらず実質「画面を開いた瞬間の1回分」しか更新を受け取れて
  // いなかったため、ポーリングに切り替える。
  static const _pollInterval = Duration(seconds: 3);

  /// 指定講義の最新ジョブをポーリング監視する。ジョブがCOMPLETEDになったら
  /// 最後の値をyieldしてポーリングを終了する(それ以上変化しないため)。
  ///
  /// ★ .distinct()が無いと、ジョブがまだ存在しない間(job==nullの間、breakの
  /// 条件に一度も触れないため)3秒ごとに同じnullを永久にyieldし続ける。
  /// これをwatchしているlectureStateProvider(async*)が毎回最初から再実行
  /// されてAsyncLoadingへ明滅し、それを見ているLectureViewerPage側のWidget
  /// (NotStartedView等)が3秒おきに丸ごと作り直される不具合になっていた
  /// (フックの状態がリセットされ、例えば「1回だけ出すはずのダイアログ」が
  /// 再度発火する)。ProcessingJobsに==/hashCodeを実装したので、内容が
  /// 実際に変わった時だけ再emitされる。
  Stream<ProcessingJobs?> watchJob(String lectureId) {
    return _watchJobRaw(lectureId).distinct();
  }

  Stream<ProcessingJobs?> _watchJobRaw(String lectureId) async* {
    // ループの外で保持する — 通信エラー時に前回値を消さずに済ませるため。
    // (以前はループの中で毎回`ProcessingJobs? job;`を宣言し直しており、
    // ポーリングが1回でも失敗すると「ジョブが存在しない」と誤って
    // yieldしてしまっていた。分析が完了した講義を開いた瞬間に通信が悪いと、
    // 一瞬「Start Analysis」状態(未分析)に見えてしまうバグの原因だった)
    ProcessingJobs? job;
    while (true) {
      var fetchSucceeded = false;
      try {
        final maps = await _supabase
            .from('processing_jobs')
            .select()
            .eq('lecture_id', lectureId)
            .timeout(networkTimeout);

        if (maps.isNotEmpty) {
          // 日付で並べ替え
          final sorted = [...maps]
            ..sort((a, b) {
              final aTime = a['created_at'] as String? ?? '';
              final bTime = b['created_at'] as String? ?? '';
              return bTime.compareTo(aTime);
            });

          try {
            job = ProcessingJobs.fromJson(sorted.first);
            fetchSucceeded = true;
          } catch (e, s) {
            dev.log('🚨 Parse Error: $e'); // エラー内容を表示
            dev.log('Stack trace: $s');
          }
        } else {
          // サーバーに問い合わせて「本当にジョブが存在しない」と確認できた
          // 場合のみnullにする。
          job = null;
          fetchSucceeded = true;
        }
      } catch (e, s) {
        // 通信エラー等。前回値(job)は変更せず、今回のyieldはスキップして
        // 次回のポーリングでリトライする。
        dev.log('🚨 watchJob poll error: $e');
        dev.log('Stack trace: $s');
      }

      if (fetchSucceeded) {
        yield job;
        if (job != null && job.status == 'COMPLETED') break;
      }
      await Future.delayed(_pollInterval);
    }
  }

  /// 指定ジョブに紐づく全タスク（進捗・エラー表示用）をポーリング監視する。
  /// 全タスクが終端状態(COMPLETED/FAILED/CANCELLED)になったらポーリングを
  /// 終了する。watchJob()と同じ理由で、内容が変わった時だけ再emitする
  /// (Listはデフォルトで内容比較の==を持たないため、要素ごとに比較する)。
  Stream<List<ProcessingTask>> watchTasksForJob(String jobId) {
    return _watchTasksForJobRaw(jobId).distinct(_tasksListEquals);
  }

  bool _tasksListEquals(List<ProcessingTask> a, List<ProcessingTask> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Stream<List<ProcessingTask>> _watchTasksForJobRaw(String jobId) async* {
    const terminalStatuses = {'COMPLETED', 'FAILED', 'CANCELLED'};

    // ループの外で保持する(watchJobと同じ理由 — 通信エラー時に前回値を
    // 空リストで潰さないため)。
    List<ProcessingTask> tasks = const [];
    while (true) {
      var fetchSucceeded = false;
      try {
        final rows = await _supabase
            .from('processing_tasks')
            .select()
            .eq('job_id', jobId)
            .timeout(networkTimeout);
        tasks = rows.map((e) => ProcessingTask.fromMap(e)).toList();
        fetchSucceeded = true;
      } catch (e, s) {
        // 通信エラー等。前回値(tasks)は変更せず、今回のyieldはスキップして
        // 次回のポーリングでリトライする。
        dev.log('🚨 watchTasksForJob poll error: $e');
        dev.log('Stack trace: $s');
      }

      if (fetchSucceeded) {
        yield tasks;

        final allTerminal =
            tasks.isNotEmpty &&
            tasks.every((t) => terminalStatuses.contains(t.status));
        if (allTerminal) break;
      }
      await Future.delayed(_pollInterval);
    }
  }

  /// 分析を開始する（Cloud RunのDAGパイプラインを起動）。
  /// アップロード完了後の自動発火(upload_manager.dart)と同じエンドポイントを叩く。
  ///
  /// [expectedChunks] にはローカルDBが持つ「録音時に実際に切り出したチャンク数」
  /// を渡すこと。★ ここを lecture_transcripts の件数から算出してはいけない ——
  /// 電波が弱く12個中5個しか届いていない状態で手動起動されると「5個で全部」と
  /// 誤認され、講義の前半だけで分析が完了してしまう(エラーにならず静かに欠落する)。
  /// nullの場合のみ、別端末からの起動などを想定してアップロード済み件数へ
  /// フォールバックする。いずれにせよサーバー側(/start-analysis)が過去ジョブの
  /// expected_chunksとも突き合わせて最大値を採るため、実績より小さい値で
  /// 走り出すことはない。
  ///
  /// [force] は「Start Over」など、ユーザーが明示的に再実行を選んだ場合のみ
  /// trueにする。既存の未完了Jobをキャンセルして新しいJobを作り直す。
  /// false(既定)の場合、既に「生きている」Jobがあればサーバー側が新規作成せず
  /// 既存Jobを返す(冪等)。FAILED/CANCELLEDのJobは生きていない扱いなので、
  /// 失敗後に音声が揃った場合はforce無しでも新しいJobが作られる。
  Future<void> startAnalysis({
    required String lectureId,
    bool force = false,
    int? expectedChunks,
  }) async {
    final resolvedExpectedChunks =
        expectedChunks ??
        await _supabase
            .from('lecture_transcripts')
            .count()
            .eq('lecture_id', lectureId)
            .timeout(networkTimeout);

    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot start analysis.');
    }

    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/start-analysis'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'lecture_id': lectureId,
            'expected_chunks': resolvedExpectedChunks,
            'force': force,
          }),
        )
        .timeout(networkTimeout);

    if (response.statusCode == 402) {
      // バックエンドの/start-analysisは{"error_code": ..., "message": ...}を
      // 想定通りのdetailとして返す(クレジット関連エラーのみ)。パースに
      // 失敗した場合は想定外の形なので汎用Exceptionにフォールバックする。
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final detail = body['detail'] as Map<String, dynamic>?;
        if (detail != null && detail['error_code'] != null) {
          throw InsufficientCreditsException(
            errorCode: detail['error_code'] as String,
            message: detail['message'] as String? ?? 'Insufficient credits.',
          );
        }
      } on InsufficientCreditsException {
        rethrow;
      } catch (_) {
        // フォールスルーして下の汎用Exceptionを投げる
      }
    }

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception(
        'Failed to start analysis (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// 指定講義の未完了ジョブ・タスクをサーバー側でCANCELLEDにする。
  /// 講義をゴミ箱に入れた直後にbest-effortで呼ぶ — これをしないと削除済み講義の
  /// パイプラインが走り続け、削除のカスケードをすり抜けたコンテンツが後から
  /// 生成されて「削除したはずの講義に全部ぶら下がる」状態になる。
  /// ジョブの行自体は消さないので、ゴミ箱から復元すればStart Analysisでやり直せる。
  Future<void> cancelJobsForLecture({required String lectureId}) async {
    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot cancel jobs.');
    }

    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/lectures/$lectureId/cancel-jobs'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
        )
        .timeout(networkTimeout);

    // 404はSupabase側にまだlectures行が無い(＝サーバー側にジョブも存在し得ない)
    // ケース。オフライン録音を一度もアップロードせずに削除した場合に起きるので、
    // エラーとして扱わない。
    if (response.statusCode == 404) return;

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to cancel jobs (${response.statusCode}): ${response.body}',
      );
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

    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/retry-task'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({'task_id': taskId}),
        )
        .timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to retry task (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// ユーザーの未完了ジョブ (status == PENDING または RUNNING) が存在するかを調べる。
  Future<bool> hasActiveProcessingJobs(String userId) async {
    try {
      final response = await _supabase
          .from('processing_jobs')
          .select('id')
          .eq('user_id', userId)
          .inFilter('status', ['PENDING', 'RUNNING'])
          .limit(1)
          .timeout(networkTimeout);
      return (response as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

}

