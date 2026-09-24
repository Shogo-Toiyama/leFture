-- Adminダッシュボードの監査ログ。
--
-- 「誰が・いつ・どのユーザーに対して・何をしたか」を全て残す。管理操作
-- (クレジット付与、停止、削除)だけでなく、PIIの開示(メールアドレスの
-- マスク解除表示)も記録対象にする —— 覗いたこと自体が記録に残らないと、
-- 「見ていない」を後から証明できないため。
--
-- クライアントからは一切触れない: RLS有効・ポリシー無し = service_role専用。
-- さらにUPDATE/DELETEはトリガで拒否する(service_roleはRLSを迂回するので、
-- ポリシーだけでは改ざんを防げない)。Adminダッシュボードは自分の足跡を
-- 消せてはならない、という不変条件をDBレベルで固定する。

CREATE TABLE public.admin_audit_log (
  id             bigserial PRIMARY KEY,
  created_at     timestamp with time zone NOT NULL DEFAULT now(),
  admin_user_id  uuid NOT NULL,
  admin_email    text,
  action         text NOT NULL,
  target_type    text,
  target_id      text,
  params         jsonb NOT NULL DEFAULT '{}'::jsonb,
  result         text NOT NULL DEFAULT 'ok',
  error_message  text,
  ip             text,
  user_agent     text
);

CREATE INDEX idx_admin_audit_log_created_at ON public.admin_audit_log USING btree (created_at DESC);
CREATE INDEX idx_admin_audit_log_target     ON public.admin_audit_log USING btree (target_type, target_id, created_at DESC);
CREATE INDEX idx_admin_audit_log_action     ON public.admin_audit_log USING btree (action, created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- 追記専用(append-only)。service_roleからのUPDATE/DELETEも含めて拒否する。
CREATE OR REPLACE FUNCTION public.admin_audit_log_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'admin_audit_log is append-only (attempted %)', TG_OP;
END;
$$;

CREATE TRIGGER trg_admin_audit_log_append_only
  BEFORE UPDATE OR DELETE ON public.admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION public.admin_audit_log_reject_mutation();

COMMENT ON TABLE public.admin_audit_log IS
  'Adminダッシュボードの全操作・全PII開示の監査ログ。追記専用(UPDATE/DELETEはトリガで拒否)。service_roleのみアクセス可。';
COMMENT ON COLUMN public.admin_audit_log.action IS
  '操作の安定タグ(例: user.email.reveal / credits.grant / user.suspend / user.delete)。';
COMMENT ON COLUMN public.admin_audit_log.params IS
  '操作の引数。講義本文・トランスクリプト等の中身は絶対に入れないこと(IDと理由だけ)。';
