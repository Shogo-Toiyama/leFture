-- Push通知(FCM)配信のためのデバイストークン管理テーブル。
--
-- 1ユーザーが複数端末(iPhone + Androidタブレット等)からログインする
-- ケースを想定し、user_idごとにdevice_tokenを複数件持てる設計にする。
-- device_tokenにUNIQUE制約を付けているのは、同一物理端末で別ユーザーへ
-- ログインし直された場合に、古いユーザーへ誤って通知が飛ぶのを防ぐため
-- (アプリ側はトークン取得のたびにUPSERTし、古い所有者の行を上書きする)。

CREATE TABLE public.user_devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    device_token text NOT NULL,
    platform text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_device_token_key UNIQUE (device_token);

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_platform_check CHECK ((platform = ANY (ARRAY['ios'::text, 'android'::text])));

CREATE INDEX idx_user_devices_user_id ON public.user_devices USING btree (user_id);

COMMENT ON TABLE public.user_devices IS 'FCM push通知配信先のデバイストークン。1ユーザーにつき複数行(複数端末)を許容する。';
COMMENT ON COLUMN public.user_devices.device_token IS 'Firebase Cloud Messagingのデバイス登録トークン。UNIQUE制約により、端末の再ログインで所有ユーザーが自動的に付け替わる。';
COMMENT ON COLUMN public.user_devices.last_used_at IS 'アプリがこのトークンを最後に送信/確認した時刻。無効化されたトークンの掃除に使う想定。';

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.user_devices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_devices_select_own ON public.user_devices FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY user_devices_insert_own ON public.user_devices FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));
CREATE POLICY user_devices_update_own ON public.user_devices FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
CREATE POLICY user_devices_delete_own ON public.user_devices FOR DELETE TO authenticated USING ((user_id = auth.uid()));
