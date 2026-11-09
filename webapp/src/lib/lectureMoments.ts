import { supabase } from './supabase';
import type { RecordingMoment } from './recordingStore';

/**
 * 録音中に付けたリアクション/メモを、アップロードで作った講義に紐づけて保存する。
 * Flutter版(lecture_moment_outbox_push_handler.dart)と同じ`lecture_moments`の行を作る。
 */
export async function insertLectureMoments(lectureId: string, moments: RecordingMoment[]): Promise<void> {
  if (moments.length === 0) return;
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const rows = moments.map((m) => ({
    id: m.id,
    user_id: userId,
    lecture_id: lectureId,
    moment_type: m.momentType,
    note_text: m.noteText,
    // smallint列(最大32767秒)。録音は最長210分=12600秒なので収まる
    timestamp_sec: Math.round(m.timestampSec),
    created_at: m.createdAt,
  }));
  const { error } = await supabase.from('lecture_moments').upsert(rows);
  if (error) throw error;
}
