import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/job/job_providers.dart';

part 'lecture_state_providers.g.dart';

// -----------------------------------------------------------------------------
// 1. 状態の定義 (Enum)
// -----------------------------------------------------------------------------

enum LectureUIState {
  loading,      // 判定中
  complete,     // 分析完了・閲覧可能
  processing,   // 分析中
  failed,       // 分析失敗
  notStarted,   // 音声はあるが分析未実施
  syncing,      // ローカルに音声はあるがクラウドにない（アップロード待ち）
}

// -----------------------------------------------------------------------------
// 2. 総合ステータス判定 (LectureState)
// -----------------------------------------------------------------------------

@riverpod
Stream<LectureUIState> lectureState(Ref ref, String lectureId) async* {
  // 1. Jobの状態を監視 (Realtime)
  final jobAsync = ref.watch(jobStreamProvider(lectureId));

  // Jobのロード中は 'loading' を返す
  if (jobAsync is AsyncLoading) {
    yield LectureUIState.loading;
    return;
  }

  final job = jobAsync.value; // Jobがない場合は null

  // --- 判定ロジック ---

  // A. Jobが存在する場合
  if (job != null) {
    if (job.status == 'COMPLETED') {
      yield LectureUIState.complete;
      return;
    }
    if (job.status == 'FAILED') {
      yield LectureUIState.failed;
      return;
    }
    // PENDING, RUNNING
    yield LectureUIState.processing;
    return;
  }

  // B. Jobが存在しない場合 -> 分析未実施
  yield LectureUIState.notStarted;
}