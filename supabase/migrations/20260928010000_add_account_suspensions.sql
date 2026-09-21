-- アカウント停止(利用規約違反への運用対処)。
--
-- user_profilesに列を足す案は不採用: user_profilesは本人がinsert/update/delete
-- できるため、行を消して作り直すだけで停止が解除できてしまう。停止情報は
-- クライアントから一切触れない(RLS有効・ポリシー無し=service_role専用)
-- 独立したテーブルに置き、バックエンドだけが読む。
--
-- 運用: 停止はこのテーブルに行をinsert、解除は行をdelete(Dashboardから手で行う)。
-- 停止中は閲覧だけを許し、録音(リアルタイム含む)・分析・クレジット購入・
-- プラン変更・その他すべての生成系操作をバックエンドで403 ACCOUNT_SUSPENDEDにする。
-- ただしサブスクの解約(Freeへの降格)は必ず通す —— 制限したまま課金だけ
-- 続ける状態を作らないため。

CREATE TABLE public.account_suspensions (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  suspended_at timestamp with time zone NOT NULL DEFAULT now(),
  reason       text,
  suspended_by text
);

ALTER TABLE public.account_suspensions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.account_suspensions IS
  '停止中アカウント。行がある=停止中。クライアントからは読み書き不可(service_roleのみ)。';
