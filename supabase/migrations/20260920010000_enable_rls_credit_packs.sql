-- 20260920000000で追加したcredit_packsにRLSを有効化し忘れていた修正。
-- subscription_plans/credit_grants(baseline)と同じ方針: ポリシーは追加せず
-- enableのみ→anon/authenticatedからは一切読み書き不可、service_role
-- (バックエンドのadmin_client)だけがRLSをバイパスしてアクセスできる。
--
-- 修正前の状態は、PostgRESTのデフォルト公開スキーマ経由でcredit_amount/
-- store_product_idを誰でも書き換えられる実害のある穴だった(例: 安価な商品の
-- credit_amountを不正に書き換えてから購入し、webhook経由で不当に大量の
-- クレジットを付与させる、という悪用が理論上可能だった)。
ALTER TABLE public.credit_packs ENABLE ROW LEVEL SECURITY;
