// lib/application/lecture/lecture_providers.dart

import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../infrastructure/local_db/app_database_provider.dart';
import '../../infrastructure/repositories/lecture_artifact_repository.dart';
import '../../infrastructure/local_db/repositories/lecture_topic_repository_drift.dart';
import 'lecture_list_provider.dart';
import '../../domain/entities/lecture_data.dart';
import '../../domain/entities/lecture.dart';

// コード生成用
part 'lecture_providers.g.dart';

// Repository自体のProvider
@riverpod
LectureArtifactRepository lectureArtifactRepository(Ref ref) {
  return LectureArtifactRepository(Supabase.instance.client, ref.watch(appDatabaseProvider));
}
// -----------------------------------------------------------------------------
// 単一の授業メタデータ（タイトル、日付など）を取得するProvider
// -----------------------------------------------------------------------------
// 以前はSupabase Realtimeで直接ストリーミングしていたが、Realtimeがどの
// テーブルでも有効化されていなかったため実質「画面を開いた瞬間の1回分」しか
// 更新を受け取れていなかった。ローカルDB経由でオフライン優先に統一する。
@riverpod
Stream<Lecture?> lecture(Ref ref, String id) {
  return ref.watch(lectureRepositoryProvider).watchLectureById(id);
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
//
// 取得成功時のみキャッシュを維持(keepAlive)する。失敗時(まだ生成されていない/
// トークン未リフレッシュ等の一時的なエラー)はキャッシュを維持せずAutoDisposeに
// 戻すことで、Widgetが再度watchされたタイミング(画面遷移・pull-to-refresh等)で
// 自然に再取得が走るようにする。失敗結果を永久にキャッシュしてしまうと、
// 一覧表示直後など最も早いタイミングでリクエストされる項目(例: 各レクチャーの
// 最初のトピック画像)が一時的なエラーを引いた場合に、実際は少し待てば取得できる
// ようになっても二度と再取得されなくなる問題があった。
@riverpod
Future<File> artifactFile(Ref ref, String storagePath) async {
  final link = ref.keepAlive();
  try {
    return await ref.watch(lectureArtifactRepositoryProvider).getArtifactFile(storagePath);
  } catch (_) {
    link.close();
    rethrow;
  }
}

// レクチャーの最初のトピック（index = 1）の image_path を監視するProvider
// (ローカルDB経由でオフライン優先)
@riverpod
Stream<String?> firstTopicImagePath(Ref ref, String lectureId) {
  return ref.watch(lectureTopicRepositoryDriftProvider).watchFirstTopicImagePath(lectureId);
}