/// バックエンドの `app/services/helpers/plan_features.py` と1対1で対応する
/// フロント側のハードコード版。tier_level(0=Free, 1=Lite, 2=Core, 3=Max)から
/// 「この機能が使えるか」を判定するだけの、状態を持たない純粋関数の集まり。
///
/// tier_levelの実際の値はGET /billing/summaryのtier_levelから取得し、既存の
/// creditSummaryProvider(アプリ全体でほぼ常時watchされている)にそのまま乗せる。
/// これ専用の新しいキャッシュ/ローカルDB永続化は用意しない — バックエンドが
/// 実際の生成・保存を最終的にプラン通りにしか行わないため、ここでの判定は
/// あくまで「ロック表示を出すか/アップグレード導線を出すか」というUI用の
/// ヒントに過ぎず、多少の反映遅れが起きても実害は無い。
///
/// 値を変える時はバックエンド側(plan_features.py)と必ず両方同時に直すこと。
library;

const int tierFree = 0;
const int tierLite = 1;
const int tierCore = 2;
const int tierMax = 3;

// --- Feature keys -----------------------------------------------------
// 全プラン共通で使える機能(ReviewCards生成, Fun Fact生成, DeepNotesの
// 1トピック目プレビュー)にはキーを割り当てない。ここに列挙するのは
// 「ゲートが必要な機能」だけ。
const String featureKeywordExtractionSubscriber = 'keyword_extraction_subscriber';
const String featureAnnouncementGeneration = 'announcement_generation';
const String featureSourceTranscriptView = 'source_transcript_view';
const String featureTopicMap = 'topic_map';
const String featureDeepNotesFull = 'deep_notes_full'; // Lite以上: 全トピック生成(Freeは1トピック目のみ)
const String featureFunFactSearch = 'fun_fact_search';
const String featureRealtimeTranscribe = 'realtime_transcribe';

const Map<String, int> _featureMinTier = {
  featureKeywordExtractionSubscriber: tierCore,
  featureAnnouncementGeneration: tierCore,
  featureSourceTranscriptView: tierCore,
  featureTopicMap: tierLite,
  featureDeepNotesFull: tierLite,
  featureFunFactSearch: tierCore,
  featureRealtimeTranscribe: tierMax,
};

/// tierLevelがfeatureKeyを使える権利を持つか判定する。
///
/// gatingDisabledはGET /billing/summaryのgating_disabledをそのまま渡す
/// (サーバー側のkill-switch兼、実機テスト用許可リストの判定結果)。
/// クライアント側にこの値を決めさせる独自ロジックは持たない — 実際の生成・保存の
/// 可否は常にバックエンドのhas_feature()が最終判断するため、ここでの判定は
/// あくまでロック表示/アップグレード導線を出すかどうかのUI用ヒントに過ぎない。
bool hasFeature(int tierLevel, String featureKey, {required bool gatingDisabled}) {
  final minTier = _featureMinTier[featureKey];
  if (minTier == null) {
    throw ArgumentError('Unknown feature_key: $featureKey');
  }
  if (gatingDisabled) return true;
  return tierLevel >= minTier;
}
