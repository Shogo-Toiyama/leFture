-- Web版サブスク決済(自前Stripe + RevenueCat連携)用。ユーザーごとに1つの
-- Stripe Customerを使い回すための列。無ければ購入のたびにCustomerが
-- 増殖してしまう(保存済み支払い方法の再利用もできなくなる)。
ALTER TABLE public.user_profiles
  ADD COLUMN stripe_customer_id text;

CREATE UNIQUE INDEX user_profiles_stripe_customer_id_uidx
  ON public.user_profiles (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;
