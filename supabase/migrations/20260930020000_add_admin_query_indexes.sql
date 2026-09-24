-- Adminダッシュボードの集計クエリが使うインデックス。
--
-- このリポジトリには今まで user_id / created_at のインデックスがほとんど無かった
-- (Postgresは外部キーにインデックスを自動作成しない)。テーブルが小さいうちは
-- シーケンシャルスキャンで足りていたが、Adminの集計は「過去30日ぶんを数える」
-- クエリを1画面で数十本走らせるため、ここで効かせておく。
--
-- ★ lectures(user_id) は Admin だけの都合ではない。RLSポリシーが
--   `auth.uid() = user_id` なので、全ユーザーの全クエリがこの条件で絞っている。
--   ここにインデックスが無いのはアプリ全体の性能問題でもある。
--
-- CONCURRENTLYは使えない(マイグレーションはトランザクション内で走るため)。
-- 現在のテーブルサイズなら一瞬で終わるが、データ量が増えてから追加する場合は
-- 手動でCONCURRENTLYを検討すること。

CREATE INDEX IF NOT EXISTS idx_lectures_user_id            ON public.lectures            USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_lectures_created_at         ON public.lectures            USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_user_id ON public.credit_transactions USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_created ON public.credit_transactions USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_credit_grants_user_id       ON public.credit_grants       USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_user_id       ON public.usage_records       USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_created_at    ON public.usage_records       USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_processing_jobs_user_id     ON public.processing_jobs     USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_processing_jobs_created_at  ON public.processing_jobs     USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_processing_jobs_lecture_id  ON public.processing_jobs     USING btree (lecture_id);
CREATE INDEX IF NOT EXISTS idx_processing_tasks_job_id     ON public.processing_tasks    USING btree (job_id);
CREATE INDEX IF NOT EXISTS idx_processing_tasks_created_at ON public.processing_tasks    USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at  ON public.support_tickets     USING btree (created_at DESC);
