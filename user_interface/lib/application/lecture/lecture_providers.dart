// lib/application/lecture/lecture_providers.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../infrastructure/repositories/lecture_artifact_repository.dart';
import '../../domain/entities/lecture_data.dart';
import '../../domain/entities/lecture.dart';

// コード生成用
part 'lecture_providers.g.dart';

// Repository自体のProvider
@riverpod
LectureArtifactRepository lectureArtifactRepository(Ref ref) {
  return LectureArtifactRepository(Supabase.instance.client);
}
// -----------------------------------------------------------------------------
// 単一の授業メタデータ（タイトル、日付など）を取得するProvider
// -----------------------------------------------------------------------------
@riverpod
Stream<Lecture?> lecture(Ref ref, String id) {
  return Supabase.instance.client
      .from('lectures')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((data) => data.isNotEmpty ? Lecture.fromMap(data.first) : null);
}

// -----------------------------------------------------------------------------
// UIから直接呼べるデータ取得用Provider (Familyを使う)
// -----------------------------------------------------------------------------

// 読む授業データを取得するProvider
// ref.watch(lectureCompleteDataProvider((uid: '...', lectureId: '...'))) で使います
@riverpod
Future<LectureCompleteData?> lectureCompleteData(
  Ref ref, {
  required String uid,
  required String lectureId,
}) {
  return ref
      .watch(lectureArtifactRepositoryProvider)
      .getLectureCompleteData(uid: uid, lectureId: lectureId);
}

// トランスクリプトを取得するProvider
@riverpod
Future<List<TranscriptSentence>?> transcript(
  Ref ref, {
  required String uid,
  required String lectureId,
}) {
  return ref
      .watch(lectureArtifactRepositoryProvider)
      .getTranscript(uid: uid, lectureId: lectureId);
}