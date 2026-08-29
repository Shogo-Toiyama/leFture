import { apiFetch, ApiError } from './api';

/**
 * バックエンドがpresigned URLをこのContent-Typeで署名しているため固定。
 * 実ファイルの拡張子(mp3/wav/flac等)に関わらずこの値を送る必要がある
 * (upload_manager.dart:568 と同じ制約)。
 */
const R2_UPLOAD_CONTENT_TYPE = 'audio/x-m4a';

export class InsufficientCreditsError extends Error {
  constructor(
    message: string,
    public errorCode: 'NO_CREDIT_ALLOCATION' | 'INSUFFICIENT_CREDITS'
  ) {
    super(message);
    this.name = 'InsufficientCreditsError';
  }
}

interface RequestUploadUrlResponse {
  upload_url: string;
  storage_path: string;
}

interface StartAnalysisResponse {
  message: string;
  job_id: string;
}

export interface UploadProgress {
  step: 'requesting-url' | 'uploading' | 'finalizing' | 'starting-analysis' | 'done';
}

export async function uploadRecordingAndAnalyze(
  lectureId: string,
  file: File,
  onProgress?: (progress: UploadProgress) => void
): Promise<string> {
  onProgress?.({ step: 'requesting-url' });
  const { upload_url } = await apiFetch<RequestUploadUrlResponse>(
    '/worker/request-master-audio-upload-url',
    { method: 'POST', body: JSON.stringify({ lecture_id: lectureId }) }
  );

  onProgress?.({ step: 'uploading' });
  const putResponse = await fetch(upload_url, {
    method: 'PUT',
    headers: { 'Content-Type': R2_UPLOAD_CONTENT_TYPE },
    body: file,
  });
  if (!putResponse.ok) {
    throw new Error(`Failed to upload audio file to storage (status ${putResponse.status})`);
  }

  onProgress?.({ step: 'finalizing' });
  await apiFetch('/worker/complete-master-audio-upload', {
    method: 'POST',
    body: JSON.stringify({ lecture_id: lectureId }),
  });

  onProgress?.({ step: 'starting-analysis' });
  const jobId = await startAnalysis(lectureId);
  onProgress?.({ step: 'done' });
  return jobId;
}

/**
 * /start-analysisを呼ぶだけの版。アップロード直後の自動起動だけでなく、
 * LectureViewerPageの手動リトライ("Start analysis"ボタン)からも使う。
 */
export async function startAnalysis(lectureId: string, force = false): Promise<string> {
  try {
    const { job_id } = await apiFetch<StartAnalysisResponse>('/start-analysis', {
      method: 'POST',
      body: JSON.stringify({ lecture_id: lectureId, expected_chunks: 0, force }),
    });
    return job_id;
  } catch (err) {
    if (err instanceof ApiError && err.status === 402) {
      const detail = err.body as { detail?: { error_code?: string; message?: string } };
      const errorCode = detail.detail?.error_code === 'NO_CREDIT_ALLOCATION' ? 'NO_CREDIT_ALLOCATION' : 'INSUFFICIENT_CREDITS';
      throw new InsufficientCreditsError(
        detail.detail?.message ?? 'Not enough credits to start analysis.',
        errorCode
      );
    }
    throw err;
  }
}
