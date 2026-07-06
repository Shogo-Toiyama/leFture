// lib/application/lecture/lecture_providers.dart

import 'dart:io';

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

// R2上の任意の成果物ファイル（トピック画像など）をローカルキャッシュ経由で取得するProvider
// storagePath 例: "{uid}/{lectureId}/images/topic_1.jpg"
@riverpod
Future<File?> artifactFile(Ref ref, String storagePath) {
  return ref.watch(lectureArtifactRepositoryProvider).getArtifactFile(storagePath);
}