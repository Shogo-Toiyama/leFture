import 'dart:async';

import 'package:lecture_companion_ui/application/topic_map/topic_map_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/topic_map_repository_supabase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_reconstruct_controller.g.dart';

/// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
/// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
/// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
/// 再取得させて画面を最新のマップに更新する。
@riverpod
class TopicMapReconstructController extends _$TopicMapReconstructController {
  @override
  FutureOr<void> build(String courseId) {
    return null;
  }

  Future<void> recreate() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(topicMapRepositoryProvider).reconstruct(courseId: courseId);
      ref.invalidate(topicMapForCourseProvider(courseId));
    });
  }
}
