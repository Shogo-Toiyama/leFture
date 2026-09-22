-- Stripe本番環境(Liveモード)のProduct ID / Price IDへの切り替え
--
-- 対象商品:
--   Lite:         sub_lite_monthly
--                 prod_id:  prod_VH81aQ47inwvPo
--                 price_id: price_1UGZloQylf53GNncphyE1ZUg
--   Core:         sub_core_monthly
--                 prod_id:  prod_VH82UaRNh1i2Aw
--                 price_id: price_1UGZm6Qylf53GNncUbqTKvTV
--   Max:          sub_max_monthly
--                 prod_id:  prod_VH82Av0m0a219M
--                 price_id: price_1UGZmQQylf53GNnc2CM0H4TL
--
--   100 Credits:  credits_100
--                 prod_id:  prod_VIsFr9ozHAfX4p
--                 price_id: price_1UIGVFQylf53GNnczD0KfJ0m
--   500 Credits:  credits_500
--                 prod_id:  prod_VIsGm7j1GsDr9F
--                 price_id: price_1UIGVqQylf53GNncgpdfSwRL
--   2000 Credits: credits_2000
--                 prod_id:  prod_VIsGSCnNXjWuOV
--                 price_id: price_1UIGWQQylf53GNnc2geEASPP

UPDATE public.subscription_plans
  SET stripe_price_id = 'price_1UGZloQylf53GNncphyE1ZUg',
      stripe_product_id = 'prod_VH81aQ47inwvPo'
  WHERE store_product_id = 'com.lefture.app.sub.starter';

UPDATE public.subscription_plans
  SET stripe_price_id = 'price_1UGZm6Qylf53GNncUbqTKvTV',
      stripe_product_id = 'prod_VH82UaRNh1i2Aw'
  WHERE store_product_id = 'com.lefture.app.sub.standard';

UPDATE public.subscription_plans
  SET stripe_price_id = 'price_1UGZmQQylf53GNnc2CM0H4TL',
      stripe_product_id = 'prod_VH82Av0m0a219M'
  WHERE store_product_id = 'com.lefture.app.sub.premium';

UPDATE public.credit_packs
  SET stripe_price_id = 'price_1UIGVFQylf53GNnczD0KfJ0m',
      stripe_product_id = 'prod_VIsFr9ozHAfX4p'
  WHERE store_product_id = 'com.lefture.app.credits.100';

UPDATE public.credit_packs
  SET stripe_price_id = 'price_1UIGVqQylf53GNncgpdfSwRL',
      stripe_product_id = 'prod_VIsGm7j1GsDr9F'
  WHERE store_product_id = 'com.lefture.app.credits.500';

UPDATE public.credit_packs
  SET stripe_price_id = 'price_1UIGWQQylf53GNnc2geEASPP',
      stripe_product_id = 'prod_VIsGSCnNXjWuOV'
  WHERE store_product_id = 'com.lefture.app.credits.2000';
