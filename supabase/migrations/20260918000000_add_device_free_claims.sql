-- 端末識別（Keychain / Device ID）によるFreeプラン重複Claim防止テーブルと関数の更新

CREATE TABLE IF NOT EXISTS public.device_free_claims (
  device_id text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id uuid NOT NULL REFERENCES public.subscription_plans(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_free_claims_user_id ON public.device_free_claims(user_id);

-- RLS設定
ALTER TABLE public.device_free_claims ENABLE ROW LEVEL SECURITY;
-- サービスロール（SECURITY DEFINER）のみ操作を許可するためポリシーは追加しないか、SELECTのみ許可

-- 旧シグネチャを削除
DROP FUNCTION IF EXISTS public.claim_plan(uuid, uuid);

CREATE OR REPLACE FUNCTION public.claim_plan(
  p_user_id   uuid,
  p_plan_id   uuid,
  p_device_id text DEFAULT NULL
)
 RETURNS user_subscription_mappings
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_mapping user_subscription_mappings;
  v_existing_claim_user_id uuid;
begin
  select * into v_plan from subscription_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'plan_not_found';
  end if;

  if v_plan.claim_mode <> 'self_serve' then
    raise exception 'plan_not_self_serve';
  end if;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    raise exception 'plan_expired';
  end if;

  -- 端末ベースでの二重Claimチェック (同一端末で別ユーザーによるClaimをブロック)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    select user_id into v_existing_claim_user_id
      from public.device_free_claims
     where device_id = p_device_id;

    if v_existing_claim_user_id is not null and v_existing_claim_user_id <> p_user_id then
      raise exception 'device_already_claimed';
    end if;
  end if;

  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id and plan_id = p_plan_id and status = 'active'
  ) then
    raise exception 'plan_already_claimed';
  end if;

  insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end)
    values (
      p_user_id, p_plan_id, 'active', now(),
      now() + (v_plan.billing_interval_months || ' months')::interval
    )
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_start = now(),
          current_period_end = excluded.current_period_end
    returning * into v_mapping;

  -- 端末Claimレコードを登録 (同一ユーザーであれば更新)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    insert into public.device_free_claims (device_id, user_id, plan_id, claimed_at)
      values (p_device_id, p_user_id, p_plan_id, now())
      on conflict (device_id) do update
        set user_id = excluded.user_id,
            plan_id = excluded.plan_id,
            claimed_at = excluded.claimed_at;
  end if;

  perform grant_credits(
    p_user_id, v_plan.monthly_credit_amount, 'subscription_initial', p_plan_id,
    v_mapping.current_period_end
  );

  return v_mapping;
end;
$function$;
