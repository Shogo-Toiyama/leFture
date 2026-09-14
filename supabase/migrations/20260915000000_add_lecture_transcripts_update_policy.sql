-- lecture_transcriptsにはINSERT/SELECTのRLSポリシーしか存在せず、UPDATE用の
-- ポリシーが無かった。クライアント側のチャンクアップロード処理は
-- upsert(onConflict: 'lecture_id,chunk_index')でこのテーブルに書き込んでおり、
-- 既に同じ(lecture_id, chunk_index)の行が存在する場合は
-- INSERT ... ON CONFLICT DO UPDATE に展開される。
--
-- PostgresのRLSでは、この競合時のUPDATE分岐を許可するにはUPDATE用ポリシーが
-- 必要になる。UPDATEポリシーが存在しないと、既に行が存在するチャンクの
-- 再アップロード(通信不安定によるリトライ等でよく発生する)が
-- 「new row violates row-level security policy (USING expression)」
-- (42501)で失敗する。
--
-- 特にRealtime Transcribeでは、クライアントが成功レスポンスを受け取る前に
-- サーバー側の処理(Cloud Run → Whisper文字起こし → レビュー)が先に進み、
-- statusがPROCESSINGより先(TRANSCRIBED/REVIEWED等)に更新されることがある。
-- この状態でクライアントが同じチャンクの再送を試みると、上記のUPDATE分岐に
-- 入って失敗する。
--
-- INSERT/SELECTポリシーと同じ所有者チェック(lectures.user_id = auth.uid())を
-- UPDATEにも適用し、upsertの競合時更新を許可する。

CREATE POLICY "Users can update their own transcripts" ON public.lecture_transcripts
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.lectures
    WHERE lectures.id = lecture_transcripts.lecture_id
      AND lectures.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.lectures
    WHERE lectures.id = lecture_transcripts.lecture_id
      AND lectures.user_id = auth.uid()
  ));
