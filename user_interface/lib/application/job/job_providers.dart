// lib/application/job/job_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../infrastructure/repositories/job_repository.dart';
import '../../domain/entities/processing_jobs.dart';
import '../../domain/entities/processing_task.dart';

part 'job_providers.g.dart';

@riverpod
JobRepository jobRepository(Ref ref) {
  return JobRepository(Supabase.instance.client);
}

@riverpod
Stream<ProcessingJobs?> jobStream(Ref ref, String lectureId) {
  return ref.watch(jobRepositoryProvider).watchJob(lectureId);
}

// ジョブに紐づく全タスク(進捗・エラー表示用)をRealtime監視するProvider
@riverpod
Stream<List<ProcessingTask>> jobTasksStream(Ref ref, String jobId) {
  return ref.watch(jobRepositoryProvider).watchTasksForJob(jobId);
}