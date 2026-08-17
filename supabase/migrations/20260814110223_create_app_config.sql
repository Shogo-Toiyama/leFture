-- アプリ全体のキルスイッチ/強制アップデート設定を保持する、常に1行だけの
-- 設定テーブル。クライアント(user_interface/lib/application/app_config/)は
-- 起動時・バックグラウンド復帰時にこの行をSELECTし、フェイルオープンで
-- 扱う(取得に失敗しても既存の状態を維持し、全ユーザーをロックしない)。
CREATE TABLE public.app_config (
  id integer PRIMARY KEY DEFAULT 1,

  -- true にすると、全端末でOutboxの書き込み同期(サーバーへのPush)が
  -- 停止する。ローカルに保存済みのデータの閲覧は妨げない。
  maintenance boolean NOT NULL DEFAULT false,

  -- メンテナンス中に表示するメッセージ。NULLの場合はアプリ側のデフォルト
  -- 文言(多言語)が使われる。
  maintenance_message text,

  -- この値未満のビルド番号(=Gitの総コミット数、CFBundleVersion/
  -- versionCodeとして自動設定される)を使っている端末には、
  -- 「アップデートが必要です」画面を表示する。0のままなら誰にも表示されない。
  min_build_number integer NOT NULL DEFAULT 0,

  -- アップデート要求時に表示するメッセージ。NULLの場合はアプリ側の
  -- デフォルト文言(多言語)が使われる。
  update_message text,

  updated_at timestamptz NOT NULL DEFAULT now(),

  -- id=1固定の単一行テーブルにする(複数行の設定を作らせない)。
  CONSTRAINT app_config_singleton CHECK (id = 1)
);

-- 常に1行だけ存在する状態で初期化しておく(平常運転)。
INSERT INTO public.app_config (id, maintenance, min_build_number)
VALUES (1, false, 0)
ON CONFLICT (id) DO NOTHING;

-- updated_atの自動更新は、既存の public.set_updated_at() を再利用する
-- (legal_documentsのマイグレーションで定義済み。プロジェクト全体の
-- 命名規則(trg_set_updated_at)に合わせる)。
DROP TRIGGER IF EXISTS trg_set_updated_at ON public.app_config;
CREATE TRIGGER trg_set_updated_at
  BEFORE UPDATE ON public.app_config
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- 全端末(未ログイン含む)から読めないと、そもそもメンテナンス判定ができない。
-- 書き込みはService Role(管理者)からのみ行う想定で、
-- INSERT/UPDATE/DELETEを許可するPolicyは意図的に作らない。
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read access for app_config" ON public.app_config;

CREATE POLICY "Allow public read access for app_config"
ON public.app_config
FOR SELECT
TO public
USING (true);
