/**
 * user_interface/lib/domain/entities/processing_task.dart:62-94 のステップ順・ラベルのTS移植。
 * TRANSCRIBE_MASTER / CHECK_AND_ASSEMBLE は排他 (アップロードかリアルタイムかで
 * どちらか一方だけが実際のタスクとして存在する) なので、表示側は実在するタスクだけを
 * この順序でフィルタして並べる。
 */
export const PROCESSING_TASK_ORDER: string[] = [
  'TRANSCRIBE_MASTER',
  'CHECK_AND_ASSEMBLE',
  'CORE_EXTRACTION',
  'ROLE_CLASSIFICATION',
  'ANNOUNCEMENT_GENERATION',
  'TOPIC_MAPPING',
  'REVIEW_CARD_GENERATION',
  'IMAGE_PROMPT_GENERATION',
  'IMAGE_RENDERING',
  'FUN_FACT_BRAINSTORMING',
  'FUN_FACT_SEARCH',
  'FUN_FACTS_GENERATION',
  'DETAIL_CONTENTS_GENERATION',
  'FIGURE_GENERATION',
  'FINALIZE_JOB',
];

export const PROCESSING_TASK_LABELS: Record<string, string> = {
  TRANSCRIBE_MASTER: 'Transcribing audio',
  CHECK_AND_ASSEMBLE: 'Assembling transcript',
  CORE_EXTRACTION: 'Extracting key topics',
  ROLE_CLASSIFICATION: 'Classifying content',
  ANNOUNCEMENT_GENERATION: 'Checking for announcements',
  TOPIC_MAPPING: 'Mapping topics',
  REVIEW_CARD_GENERATION: 'Generating review cards',
  IMAGE_PROMPT_GENERATION: 'Preparing topic art',
  IMAGE_RENDERING: 'Rendering topic arts',
  FUN_FACT_BRAINSTORMING: 'Brainstorming fun facts',
  FUN_FACT_SEARCH: 'Researching fun facts',
  FUN_FACTS_GENERATION: 'Writing fun facts',
  DETAIL_CONTENTS_GENERATION: 'Writing deep notes',
  FIGURE_GENERATION: 'Generating diagrams',
  FINALIZE_JOB: 'Finalizing',
};

export const PROCESSING_TASK_LABELS_JA: Record<string, string> = {
  TRANSCRIBE_MASTER: '音声を文字起こし中',
  CHECK_AND_ASSEMBLE: '文字起こしデータを準備中',
  CORE_EXTRACTION: '重要トピックを抽出中',
  ROLE_CLASSIFICATION: '話者ロールを分類中',
  ANNOUNCEMENT_GENERATION: 'お知らせ・要連絡事項を抽出中',
  TOPIC_MAPPING: 'トピックマップを生成中',
  REVIEW_CARD_GENERATION: '復習カードを生成中',
  IMAGE_PROMPT_GENERATION: 'トピックアートをデザイン中',
  IMAGE_RENDERING: 'トピックアートをレンダリング中',
  FUN_FACT_BRAINSTORMING: '関連トリビアの構想中',
  FUN_FACT_SEARCH: '関連トリビアを検索中',
  FUN_FACTS_GENERATION: '関連トリビアを執筆中',
  DETAIL_CONTENTS_GENERATION: '詳細ノート（Deep Notes）を執筆中',
  FIGURE_GENERATION: '図解を生成中',
  FINALIZE_JOB: '解析結果の最終処理中',
};

export function taskLabel(taskType: string, lang: 'ja' | 'en' = 'en'): string {
  const dict = lang === 'ja' ? PROCESSING_TASK_LABELS_JA : PROCESSING_TASK_LABELS;
  return dict[taskType] ?? PROCESSING_TASK_LABELS[taskType] ?? taskType;
}

/**
 * やり直しても結果が変わらない失敗のコード(バックエンド app/services/helpers/task_errors.py、
 * Flutter ProcessingTask.failureCode と同じ)。バックエンドはこの種の失敗だけ
 * error_message を "CODE: message" で書く。該当しなければ null。
 */
export const NO_SPEECH_DETECTED = 'NO_SPEECH_DETECTED';
export const AUDIO_NOT_UPLOADED = 'AUDIO_NOT_UPLOADED';
export type TaskFailureCode = typeof NO_SPEECH_DETECTED | typeof AUDIO_NOT_UPLOADED;

export function taskFailureCode(task: { status: string; error_message: string | null }): TaskFailureCode | null {
  if ((task.status !== 'FAILED' && task.status !== 'ERROR') || !task.error_message) return null;
  for (const code of [NO_SPEECH_DETECTED, AUDIO_NOT_UPLOADED] as const) {
    if (task.error_message.startsWith(`${code}:`)) return code;
  }
  return null;
}

export const TASK_FAILURE_TEXT_KEYS = {
  [NO_SPEECH_DETECTED]: { title: 'taskFailureNoSpeechTitle', message: 'taskFailureNoSpeechMessage' },
  [AUDIO_NOT_UPLOADED]: { title: 'taskFailureAudioNotUploadedTitle', message: 'taskFailureAudioNotUploadedMessage' },
} as const;
