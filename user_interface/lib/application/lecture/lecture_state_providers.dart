import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';

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
  error,        // ジョブ状態の取得に失敗し、本当に未実施かどうか判定できない
}

// -----------------------------------------------------------------------------
// 2. 総合ステータス判定 (LectureState)
// -----------------------------------------------------------------------------

@riverpod
Stream<LectureUIState> lectureState(Ref ref, String lectureId) async* {
  // 0. チュートリアル講義(ローカルのみ・音声もジョブも存在しない)は、
  // ジョブの有無に関わらず常に完了扱いにする。これがないと「Jobが存在しない」
  // ケースに引っかかってnotStarted(Start Analysis待ち)扱いになってしまう。
  final lectureAsync = ref.watch(lectureProvider(lectureId));
  final lecture = lectureAsync.asData?.value;
  if (lecture?.metadata?['is_tutorial'] == true) {
    yield LectureUIState.complete;
    return;
  }

  // 1. Jobの状態を監視 (Realtime)
  final jobAsync = ref.watch(jobStreamProvider(lectureId));

  // Jobのロード中は 'loading' を返す
  if (jobAsync is AsyncLoading) {
    yield LectureUIState.loading;
    return;
  }

  // 取得エラーで前回値も無い場合、jobAsync.valueはnullを返すため、これを
  // 素通りさせると「本当にJobが存在しない(未実施)」と区別が付かず、
  // Start Analysisボタンを誤って表示してしまう。前回値があればそれを使って
  // 通常判定を続け、無ければ「判定不能」として明示的にerror扱いにする。
  if (jobAsync is AsyncError && !jobAsync.hasValue) {
    yield LectureUIState.error;
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
    // FAILED/ERROR は「もう自力では進まない」終端。ERRORは旧pipeline.pyが書く値で、
    // これを拾わないと永久に「解析中」の表示のまま止まって見える。
    if (job.status == 'FAILED' || job.status == 'ERROR') {
      yield LectureUIState.failed;
      return;
    }
    // CANCELLEDは「講義削除時のジョブ停止」または「Start Overによる作り直し」で
    // 打ち切られたジョブ。バックエンドの/start-analysisもこれを終端(DEAD)として
    // 扱い、force無しで新しいジョブを作り直せるので、UIも未実施に戻す。
    if (job.status == 'CANCELLED') {
      yield LectureUIState.notStarted;
      return;
    }
    // PENDING, RUNNING
    yield LectureUIState.processing;
    return;
  }

  // B. Jobが存在しない場合 -> 分析未実施
  yield LectureUIState.notStarted;
}