-- ユーザーの利用状況を「明示的に」記録するテーブル。
--
-- ■ なぜ必要か
-- これまでアクティブユーザーを測る手段が無かった。auth.users.last_sign_in_at は
-- 使えない —— GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)
-- のときだけで、リフレッシュトークンによるセッション更新では更新されないため。
-- Supabaseクライアントはセッションをローカルに保存して裏で無期限にリフレッシュ
-- し続けるので、「毎日使っているがlast_sign_in_atは3ヶ月前」が普通に起きる。
-- あれが意味するのは「最後に再ログインを強いられた時刻」であって、利用頻度の
-- 逆指標に近い(使い続けている人ほど古くなる)。
--
-- ■ なぜ機能テーブルのupdated_atから推測しないのか
-- lectures / review_cards / fun_facts ... の更新時刻をUNIONして推測する案は却下した。
--   1. 「保存・いいね・注釈」は一部の熱心なユーザーしかやらない。母数の計測に使えない
--   2. 機能が増えるたびに集計側の定義を更新し続ける必要があり、更新し忘れた機能は
--      静かに計測から漏れる。誰も気づかないまま数字が実態から乖離していく
-- 推測をやめて、クライアントが「使っている」と明示的に書き込む1経路に集約する。
--
-- ■ なぜ1時間粒度なのか、なぜ行が増えないのか
-- PRIMARY KEY が (user_id, bucket_at, platform) なので、クライアントが10分おきに
-- pingを打っても、同じ1時間の中では既存行のUPSERTに畳み込まれる。つまり
-- 行数は「実際に触った時間数」しか増えない(1人1日あたり数行)。
-- 一方 ping_count はその1時間内に何回pingが届いたかを持つので、
-- 「その1時間ずっと使っていた(count=6)」と「ちょっと開いただけ(count=1)」を
-- 区別できる。行数据え置きで時間内の解像度が得られる。
--
-- ■ 日単位の集計もこのテーブルから出せる
-- DAU = bucket_atを日に丸めてcount(distinct user_id)。日次テーブルは別に要らない。

CREATE TABLE public.user_activity_hours (
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- UTCの時で切り捨てた時刻 (date_trunc('hour', now()))
  bucket_at         timestamp with time zone NOT NULL,
  platform          text NOT NULL,
  -- クライアントのUTCオフセット(分)。東が正: 東京=+540, ロサンゼルス=-420。
  -- ★ JavaScriptのDate.getTimezoneOffset()は符号が逆(LA=+420)なので、
  --   webapp側は必ず符号を反転して送ること。
  --   Flutterの DateTime.now().timeZoneOffset.inMinutes はそのままでよい。
  -- 「何時に使われているか」はユーザーのローカル時刻で見ないと意味が無い
  -- (UTCで集計すると日本とアメリカの利用者が混ざって分布が潰れる)ため、
  -- ここを持っておいてローカル時刻のヒストグラムを後から復元できるようにする。
  tz_offset_minutes smallint,
  first_seen_at     timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at      timestamp with time zone NOT NULL DEFAULT now(),
  ping_count        integer NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, bucket_at, platform)
);

-- 「この期間にアクティブだった人数」「日次・時間帯の分布」は全て
-- bucket_atのレンジスキャンなので、時刻を先頭にしたインデックスが要る
-- (PRIMARY KEYはuser_id先頭なのでこの用途には効かない)。
CREATE INDEX idx_user_activity_hours_bucket
  ON public.user_activity_hours USING btree (bucket_at DESC, user_id);

ALTER TABLE public.user_activity_hours ENABLE ROW LEVEL SECURITY;
-- ポリシーは作らない。書き込みは下の touch_activity() (SECURITY DEFINER)経由のみ、
-- 読み取りはservice_role(=Adminダッシュボード)のみ。
-- 将来「◯日連続で学習中!」のような表示を作るなら、そのときSELECT own ポリシーを足す。

COMMENT ON TABLE public.user_activity_hours IS
  'ユーザーがアプリを使っていた1時間ごとの記録。クライアントからはtouch_activity()経由でのみ書き込める。';


-- ---------------------------------------------------------------------------
-- ping本体
--
-- SECURITY DEFINER にして中で auth.uid() を使うのが要点 —— クライアントは
-- user_idを指定できないので、他人の活動を偽装できない。
--
-- バックエンド(Cloud Run)を経由せず、クライアントからSupabaseへ直接RPCする。
-- 全ユーザーの日常的な書き込みのためにCloud Runを起こす理由が無いし、
-- auth.uid()を使う以上、間に何かを挟んでも安全性は上がらないため。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_activity(
  p_platform text,
  p_tz_offset_minutes integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_platform text;
  v_offset smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- クライアントの実装ミスでpingが丸ごと失敗することが無いように、
  -- 想定外の値はエラーにせず 'unknown' に寄せる。計測のための記録が
  -- アプリの動作を壊してはいけない。
  v_platform := lower(coalesce(p_platform, ''));
  IF v_platform NOT IN ('web', 'ios', 'android', 'macos', 'windows', 'linux') THEN
    v_platform := 'unknown';
  END IF;

  -- 実在するUTCオフセットは -12:00 〜 +14:00。範囲外は捨てる。
  v_offset := CASE
    WHEN p_tz_offset_minutes BETWEEN -720 AND 840 THEN p_tz_offset_minutes::smallint
    ELSE NULL
  END;

  INSERT INTO public.user_activity_hours (user_id, bucket_at, platform, tz_offset_minutes)
  VALUES (v_uid, date_trunc('hour', now()), v_platform, v_offset)
  ON CONFLICT (user_id, bucket_at, platform) DO UPDATE
    SET last_seen_at      = now(),
        ping_count        = user_activity_hours.ping_count + 1,
        tz_offset_minutes = coalesce(EXCLUDED.tz_offset_minutes,
                                     user_activity_hours.tz_offset_minutes);
END;
$$;

-- これだけはログイン中のユーザー本人が呼ぶ(admin_*関数と違いservice_role専用にしない)。
REVOKE ALL ON FUNCTION public.touch_activity(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.touch_activity(text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.touch_activity(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_activity(text, integer) TO service_role;


-- ---------------------------------------------------------------------------
-- 過去分のバックフィル
--
-- 講義の作成とクレジットの消費は「アプリを使ったなら必ず起きている」イベントなので、
-- 過去の利用時刻の推定として妥当。これで初日からグラフが埋まる。
-- platformは判別できないので 'unknown'、tz_offsetも当然不明。
-- 今後クライアントが打つpingは実データなので、'unknown'かどうかで
-- 「推定で埋めた過去」と「実測」を区別できる。
-- ---------------------------------------------------------------------------
INSERT INTO public.user_activity_hours (user_id, bucket_at, platform, first_seen_at, last_seen_at, ping_count)
SELECT
  ev.user_id,
  date_trunc('hour', ev.occurred_at),
  'unknown',
  min(ev.occurred_at),
  max(ev.occurred_at),
  1
FROM (
  SELECT user_id, created_at AS occurred_at FROM public.lectures            WHERE user_id IS NOT NULL
  UNION ALL
  SELECT user_id, created_at AS occurred_at FROM public.credit_transactions WHERE user_id IS NOT NULL
) ev
GROUP BY ev.user_id, date_trunc('hour', ev.occurred_at)
ON CONFLICT (user_id, bucket_at, platform) DO NOTHING;
