-- クライアント(Flutter)で起きた予期せぬエラーの収集。
--
-- 背景: これまでアプリは生の例外文字列を画面にそのまま出していた。ユーザーには
-- 意味不明で不安を与える一方、開発者にはリリースビルドのクラッシュが一切届いて
-- いなかった(ErrorWidget.builderが未設定なので、build中の例外はreleaseでは
-- 灰色のボックスになって消える)。ここに集めて、1日2回ダイジェストメールで通知し、
-- 管理者ダッシュボードから参照する。
--
-- 2テーブルに分ける理由:
--   client_error_groups … fingerprint単位の集計。ダッシュボードとメールが見るのはこちら。
--                         1つのバグが何万回起きても1行。
--   client_error_events  … 全文コンテキスト付きの個別サンプル。容量が要るので
--                          「1グループ12時間あたり数件」までに絞り、30日で消す。
--
-- fingerprintはクライアントが計算する(code|origin|正規化済みメッセージ のSHA-256)。
-- 正規化でUUID・連番・パス・バイト数が潰れるので、1文字違うだけでは別グループに
-- ならない。詳細は user_interface/lib/domain/errors/app_error.dart を参照。
--
-- RLSはaccount_suspensionsと同じ方針 —— 有効化した上でポリシーを1つも作らない
-- (=service_role専用)。エラー本文には他ユーザーのIDやストレージパスが混ざり得るため、
-- クライアントからは一切読めてはならない。書き込みもバックエンド経由のみ。

-- ---------------------------------------------------------------
-- グループ(集計)
-- ---------------------------------------------------------------
CREATE TABLE public.client_error_groups (
  fingerprint           text PRIMARY KEY,

  code                  text NOT NULL,
  origin                text NOT NULL,
  -- 正規化後のメッセージ。グループの「顔」としてダッシュボードとメールに出す。
  normalized_message    text,
  -- 直近の生メッセージ。正規化で潰れた具体値を1つだけ手元に残す。
  sample_message        text,

  first_seen_at         timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at          timestamp with time zone NOT NULL DEFAULT now(),
  total_count           bigint NOT NULL DEFAULT 0,

  -- 影響範囲。ユーザー数は「この講義だけ壊れている」のか
  -- 「全員壊れている」のかを一目で分けるための最重要指標。
  affected_user_ids     uuid[] NOT NULL DEFAULT '{}',
  affected_device_ids   text[] NOT NULL DEFAULT '{}',
  app_versions          text[] NOT NULL DEFAULT '{}',
  platforms             text[] NOT NULL DEFAULT '{}',

  -- open: 未対応 / acknowledged: 認識済み / resolved: 修正済み /
  -- ignored: 既知のノイズ。ignoredはダイジェストメールから除外される。
  status                text NOT NULL DEFAULT 'open',
  notes                 text,

  -- ダイジェストの差分判定。last_notified時点のtotal_countを覚えておき、
  -- 「新規 or 前回より増えた」グループだけをメールに載せる。
  last_notified_at      timestamp with time zone,
  count_at_last_notify  bigint NOT NULL DEFAULT 0,

  CONSTRAINT client_error_groups_status_check
    CHECK (status IN ('open', 'acknowledged', 'resolved', 'ignored'))
);

ALTER TABLE public.client_error_groups ENABLE ROW LEVEL SECURITY;

-- ダイジェストは「ignoredでなく、前回通知時より増えた」行を引く。
CREATE INDEX client_error_groups_digest_idx
  ON public.client_error_groups (status, last_seen_at DESC);

-- ダッシュボードの既定ソート(新しい順 / 多い順)。
CREATE INDEX client_error_groups_count_idx
  ON public.client_error_groups (total_count DESC);

COMMENT ON TABLE public.client_error_groups IS
  'クライアントのエラーをfingerprint単位で集計したもの。service_role専用。statusをignoredにするとダイジェストメールから外れる。';

-- ---------------------------------------------------------------
-- イベント(サンプル)
-- ---------------------------------------------------------------
CREATE TABLE public.client_error_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fingerprint       text NOT NULL REFERENCES public.client_error_groups(fingerprint) ON DELETE CASCADE,

  -- 未ログイン時(サインイン画面のエラー)はuser_idがNULLになる。
  -- そのケースこそ一番知りたいので、NOT NULLにはしない。
  user_id           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  device_id         text NOT NULL,

  occurred_at       timestamp with time zone NOT NULL,
  received_at       timestamp with time zone NOT NULL DEFAULT now(),

  -- この1行が代表している発生回数。クライアント側の3段デデュープで
  -- まとめられた件数が入る(エラー嵐でも行は増えない)。
  occurrence_count  integer NOT NULL DEFAULT 1,

  code              text NOT NULL,
  origin            text NOT NULL,
  raw_message       text,
  stack             text,
  -- エラー直前のDevLog末尾。何をしていて落ちたかの手掛かり。
  breadcrumbs       jsonb,

  http_status       integer,
  backend_code      text,

  route             text,
  app_version       text,
  platform          text,
  os_version        text,
  locale            text,
  is_authenticated  boolean NOT NULL DEFAULT false,

  -- ユーザーに見せた参照コード(ERR-7K2M9Q)。問い合わせとの突合に使う。
  ref_code          text
);

ALTER TABLE public.client_error_events ENABLE ROW LEVEL SECURITY;

CREATE INDEX client_error_events_fingerprint_idx
  ON public.client_error_events (fingerprint, received_at DESC);

-- 参照コードでの逆引き(ユーザーが問い合わせに貼ってきたコードから辿る)。
CREATE INDEX client_error_events_ref_code_idx
  ON public.client_error_events (ref_code);

-- レート制限の判定(device_idの直近1時間の件数)と、30日パージに使う。
CREATE INDEX client_error_events_device_idx
  ON public.client_error_events (device_id, received_at DESC);

COMMENT ON TABLE public.client_error_events IS
  'クライアントエラーの個別サンプル。全件ではなく、1グループあたり一定数までのサンプルのみ。30日でpatrolが削除する。service_role専用。';
