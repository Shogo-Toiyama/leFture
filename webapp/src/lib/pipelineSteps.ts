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
  FINALIZE_JOB: 'Finalizing',
};

export function taskLabel(taskType: string): string {
  return PROCESSING_TASK_LABELS[taskType] ?? taskType;
}
