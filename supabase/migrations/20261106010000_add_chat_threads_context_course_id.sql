-- スレッドをコースの画面から開始した場合、そのコース(context_lecture_id と同じ扱い)。
-- 後でコースの画面以外から続けても、探索役・回答役がそのコースの話だと分かるようにする。
-- 講義を見ているときは講義からコースが分かるので、ここには入れない(context_lecture_id だけ)。
ALTER TABLE public.chat_threads
    ADD COLUMN IF NOT EXISTS context_course_id uuid;

-- コースが物理削除されてもスレッド自体は残す(文脈のコースが無くなるだけ)。
ALTER TABLE ONLY public.chat_threads
    ADD CONSTRAINT chat_threads_context_course_id_fkey
    FOREIGN KEY (context_course_id) REFERENCES public.courses(id) ON DELETE SET NULL;
