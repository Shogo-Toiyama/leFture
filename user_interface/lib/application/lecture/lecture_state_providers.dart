import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
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
  noAudio,      // 音声自体がない
}

// -----------------------------------------------------------------------------
// 2. 音声ステータス (AudioStatus)
// -----------------------------------------------------------------------------

class AudioStatus {
  final bool hasLocalAudio;
  final bool hasCloudAudio;

  const AudioStatus({
    required this.hasLocalAudio,
    required this.hasCloudAudio,
  });
}

@riverpod
Future<AudioStatus> audioStatus(Ref ref, String lectureId) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) {
    return const AudioStatus(hasLocalAudio: false, hasCloudAudio: false);
  }

  // A. ローカルファイルの確認
  final dir = await getApplicationDocumentsDirectory();
  final localPath = p.join(dir.path, 'lectures', lectureId, 'audio', 'recording.m4a');
  final hasLocal = File(localPath).existsSync();

  // B. クラウド (Supabase) の確認
  // lecture_assets テーブルに type='audio' のレコードがあるか確認
  // (同期を待たず確実に判定するため、直接Supabaseに問い合わせます)
  final res = await supabase
      .from('lecture_assets')
      .count()
      .eq('lecture_id', lectureId)
      .eq('type', 'audio');
  
  final hasCloud = res > 0;

  return AudioStatus(hasLocalAudio: hasLocal, hasCloudAudio: hasCloud);
}

// -----------------------------------------------------------------------------
// 3. 総合ステータス判定 (LectureState)
// -----------------------------------------------------------------------------

@riverpod
Stream<LectureUIState> lectureState(Ref ref, String lectureId) async* {
  // 1. Jobの状態を監視 (Realtime)
  final jobAsync = ref.watch(jobStreamProvider(lectureId));
  
  // 2. 音声の状態を取得 (Future)
  // ※ 音声状態の変化（アップロード完了など）も検知したい場合、ここをStreamにするか
  // UI側でリフレッシュする工夫が必要ですが、まずはFutureで判定します。
  final audioAsync = await ref.watch(audioStatusProvider(lectureId).future);

  // Jobのロード中は 'loading' を返す
  if (jobAsync is AsyncLoading) {
    yield LectureUIState.loading;
    return;
  }

  final job = jobAsync.value; // Jobがない場合は null

  // --- 判定ロジック ---

  // A. Jobが存在する場合
  if (job != null) {
    if (job.status == 'DONE') {
      yield LectureUIState.complete;
      return;
    }
    if (job.status == 'ERROR') {
      yield LectureUIState.failed;
      return;
    }
    // PENDING, PROCESSING
    yield LectureUIState.processing;
    return;
  }

  // B. Jobが存在しない場合 -> 音声の有無で判定
  if (audioAsync.hasCloudAudio) {
    // クラウドに音声があるなら、分析開始できる
    yield LectureUIState.notStarted;
  } else if (audioAsync.hasLocalAudio) {
    // ローカルにしかない -> アップロード待ち
    yield LectureUIState.syncing;
  } else {
    // どこにもない
    yield LectureUIState.noAudio;
  }
}