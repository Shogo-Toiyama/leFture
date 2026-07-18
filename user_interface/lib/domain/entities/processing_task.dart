/// パイプラインDAGの1タスク分（`processing_tasks`テーブルの1行）
class ProcessingTask {
  const ProcessingTask({
    required this.id,
    required this.jobId,
    required this.taskType,
    required this.status,
    required this.updatedAt,
    this.errorMessage,
  });

  final String id;
  final String jobId;
  final String taskType;
  final String status; // PENDING / QUEUED / RUNNING / COMPLETED / FAILED / CANCELLED
  final DateTime updatedAt;
  final String? errorMessage;

  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
  bool get isCancelled => status == 'CANCELLED';

  /// Cloud Tasksのリトライ(maxAttempts: 5, ~2分以内に使い切る設定)が
  /// 尽きたとみなせるしきい値。これを超えてFAILEDのまま動きがなければ、
  /// もう自動では復帰しないと判断してよい。
  static const staleFailedThreshold = Duration(minutes: 5);

  bool get isStaleFailed =>
      isFailed && DateTime.now().toUtc().difference(updatedAt.toUtc()) > staleFailedThreshold;

  factory ProcessingTask.fromMap(Map<String, dynamic> map) {
    return ProcessingTask(
      id: map['id'] as String,
      jobId: map['job_id'] as String,
      taskType: map['task_type'] as String,
      status: map['status'] as String? ?? 'PENDING',
      updatedAt: DateTime.parse(map['updated_at'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }
}

/// main.py の tasks_blueprint と同じ並び順（表示・進捗計算の基準に使う）
/// TRANSCRIBE_MASTER と CHECK_AND_ASSEMBLE は互いに排他的（どちらか一方が最初のタスク）
const List<String> processingTaskOrder = [
  'TRANSCRIBE_MASTER',
  'CHECK_AND_ASSEMBLE',
  'CORE_EXTRACTION',
  'ROLE_CLASSIFICATION',
  'ANNOUNCEMENT_GENERATION',
  'TOPIC_MAPPING',
  'REVIEW_CARD_GENERATION',
  'IMAGE_PROMPT_GENERATION',
  'IMAGE_RENDERING',
  'FUN_FACT_SEARCH',
  'FUN_FACTS_GENERATION',
  'DETAIL_CONTENTS_GENERATION',
  'FINALIZE_JOB',
];

const Map<String, String> processingTaskLabels = {
  'TRANSCRIBE_MASTER': 'Transcribing audio',
  'CHECK_AND_ASSEMBLE': 'Preparing transcript',
  'CORE_EXTRACTION': 'Extracting key topics',
  'ROLE_CLASSIFICATION': 'Classifying speaker roles',
  'ANNOUNCEMENT_GENERATION': 'Finding announcements',
  'TOPIC_MAPPING': 'Mapping topics',
  'REVIEW_CARD_GENERATION': 'Generating review cards',
  'IMAGE_PROMPT_GENERATION': 'Designing topic art',
  'IMAGE_RENDERING': 'Rendering topic arts',
  'FUN_FACT_SEARCH': 'Searching fun facts',
  'FUN_FACTS_GENERATION': 'Writing fun facts',
  'DETAIL_CONTENTS_GENERATION': 'Writing deep notes',
  'FINALIZE_JOB': 'Finalizing',
};

String processingTaskLabel(String taskType) =>
    processingTaskLabels[taskType] ?? taskType;

/// main.py の tasks_blueprint と同じ依存関係（表示専用のミラー。実行時の正は
/// バックエンドが processing_tasks.dependencies から都度計算する）
/// TRANSCRIBE_MASTER と CHECK_AND_ASSEMBLE は互いに排他的（どちらか一方が最初のタスク）
const Map<String, List<String>> processingTaskDependencies = {
  'TRANSCRIBE_MASTER': [],
  'CHECK_AND_ASSEMBLE': [],
  'CORE_EXTRACTION': ['CHECK_AND_ASSEMBLE', 'TRANSCRIBE_MASTER'],
  'ROLE_CLASSIFICATION': ['CORE_EXTRACTION'],
  'ANNOUNCEMENT_GENERATION': ['ROLE_CLASSIFICATION'],
  'TOPIC_MAPPING': ['ROLE_CLASSIFICATION'],
  'REVIEW_CARD_GENERATION': ['TOPIC_MAPPING'],
  'IMAGE_PROMPT_GENERATION': ['REVIEW_CARD_GENERATION'],
  'IMAGE_RENDERING': ['IMAGE_PROMPT_GENERATION'],
  'FUN_FACT_SEARCH': ['CORE_EXTRACTION'],
  'FUN_FACTS_GENERATION': ['REVIEW_CARD_GENERATION', 'FUN_FACT_SEARCH'],
  'DETAIL_CONTENTS_GENERATION': ['REVIEW_CARD_GENERATION'],
  'FINALIZE_JOB': [
    'ANNOUNCEMENT_GENERATION',
    'IMAGE_RENDERING',
    'FUN_FACTS_GENERATION',
    'DETAIL_CONTENTS_GENERATION',
  ],
};

/// 指定したtask_type自身と、それに(直接・間接に)依存している全ての後続task_typeを返す。
/// カスケードリトライの確認ダイアログで「あわせて再実行される後続ステップ」を
/// プレビューするための表示専用ヘルパー。
Set<String> downstreamOf(String taskType) {
  final forward = <String, List<String>>{};
  processingTaskDependencies.forEach((type, deps) {
    for (final dep in deps) {
      forward.putIfAbsent(dep, () => []).add(type);
    }
  });

  final affected = <String>{};
  final queue = [taskType];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!affected.add(current)) continue;
    queue.addAll(forward[current] ?? const []);
  }
  return affected;
}
