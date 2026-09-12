-- プランカードのマーケティング用サブタイトルと、表示順を決める階層番号を追加。
--
-- subtitleは当初subtitle_en/subtitle_jaの2カラムで設計したが、言語が増える
-- たびにカラム追加が要る設計は避けたいというフィードバックを受けて、
-- jsonb 1列(言語コード→文字列)に変更した。例: {"en": "...", "ja": "..."}
--
-- tier_levelは「Free→Entry→Standard→Premiumの意図した並び順」を明示する。
-- 今までmonthly_credit_amount昇順でソートしていたが、Freeのcredit量を
-- 暫定的に1500(Entryの1200より多い)にしている関係で、金額順ソートだと
-- Entry, Free, Standard, Premiumという意図しない順序になってしまっていた。

ALTER TABLE public.subscription_plans
  ADD COLUMN subtitles jsonb,
  ADD COLUMN tier_level smallint;

-- 4プラン分のプレースホルダーコピー + 表示順。name一致で更新する
-- (このマイグレーション作成時点でUUIDを直接引用できないため。
--  disabled_at IS NULLで、無効化済みの旧"Welcome Bonus"行は触らない)。

UPDATE public.subscription_plans
  SET subtitles = '{"en": "Start your learning journey", "ja": "学びの旅を始めよう"}'::jsonb,
      tier_level = 0
  WHERE name = 'Free' AND disabled_at IS NULL;

UPDATE public.subscription_plans
  SET subtitles = '{"en": "Perfect for regular study", "ja": "日々の学習にぴったり"}'::jsonb,
      tier_level = 1
  WHERE name = 'Entry' AND disabled_at IS NULL;

UPDATE public.subscription_plans
  SET subtitles = '{"en": "For serious, consistent learners", "ja": "本気で学びたい人へ"}'::jsonb,
      tier_level = 2
  WHERE name = 'Standard' AND disabled_at IS NULL;

UPDATE public.subscription_plans
  SET subtitles = '{"en": "Unlock your full potential", "ja": "可能性を最大限に引き出そう"}'::jsonb,
      tier_level = 3
  WHERE name = 'Premium' AND disabled_at IS NULL;
