// lib/application/job/job_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../infrastructure/repositories/job_repository.dart';
import '../../domain/entities/processing_jobs.dart';

part 'job_providers.g.dart';

@riverpod
JobRepository jobRepository(Ref ref) {
  return JobRepository(Supabase.instance.client);
}

@riverpod
Stream<ProcessingJobs?> jobStream(Ref ref, String lectureId) {
  return ref.watch(jobRepositoryProvider).watchJob(lectureId);
}