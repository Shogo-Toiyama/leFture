// lib/infrastructure/repositories/job_repository.dart
import 'dart:developer' as dev;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/processing_jobs.dart'; // クラス名を確認してください

class JobRepository {
  final SupabaseClient _supabase;

  JobRepository(this._supabase);

  Stream<ProcessingJobs?> watchJob(String lectureId) {
    dev.log('👀 Start watching Job for: $lectureId');
    
    return _supabase
        .from('processing_jobs')
        .stream(primaryKey: ['id'])
        .eq('lecture_id', lectureId)
        .map((maps) {
          if (maps.isEmpty) {
            dev.log('📭 Job list is empty');
            return null;
          }

          // 日付で並べ替え
          maps.sort((a, b) {
             final aTime = a['created_at'] as String? ?? '';
             final bTime = b['created_at'] as String? ?? '';
             return bTime.compareTo(aTime);
          });

          final latestMap = maps.first;
          dev.log('📄 Processing map: $latestMap'); // ★ここ重要：生データを見る

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

  Future<void> startAnalysis({required String lectureId}) async {
    await _supabase.from('processing_jobs').insert({
      'lecture_id': lectureId,
    });
  }
}