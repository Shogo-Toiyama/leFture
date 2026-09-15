-- クレジット履歴の「-2000」誤表示 / 「Core表示なのに残高0」バグの根本修正。
--
-- 背景: credit_grantsの失効(expires_at超過)はこれまで純粋に読み取り時の
-- フィルタ(remaining_amount > 0 and expires_at > now())だけで「無かったこと」に
-- しており、remaining_amountを0にする処理もcredit_transactionsへの記録も
-- 一切無かった。このため:
--   1. /billing/historyが消費額をbalance_afterの差分で計算しており、
--      静かに消えた失効分が次の消費行(LECTURE_ANALYSIS等)に丸ごと
--      乗ってしまい、実際は-60の分析が「-2000」に見えていた。
--   2. ストア課金の付与はexpires_at=current_period_end(Sandboxでは約5分後)で
--      切れるが、user_subscription_mappings.statusはRevenueCatのwebhookが
--      届くまでactiveのまま。この谷間で「Core表示・残高0」になり、
--      /start-analysisが402を返して分析をブロックする実害もあった。
--
-- 方針: 失効を「遅延実体化(lazy materialization)」する。クレジットを
-- 読み書きするすべての関数の先頭で、そのユーザーの失効済みグラントを
-- その場でゼロ化し、対応するcredit_transactions行(reason='credit_expired')を
-- 必ず1行残す。これによりgrant/consume/webhook/更新のどの経路を通っても
-- 「remaining_amountの減少には必ず対応する台帳行がある」という不変条件が
-- 保たれ、historyの計算をdelta合計に直すだけで表示が正しくなる。
--
-- 30分毎の一括スイープ(バルクUPDATE)は不採用: credit_grantsに索引が無く
-- 全表スキャンになる上、consume_credits()のロック順(expires_at, created_at)と
-- 衝突してデッドロックしうる。かわりに各関数内でそのユーザー1人分だけを
-- FOR UPDATEでロックする、ユーザーごとに独立したトランザクションの
-- lazy materializationを採用する。長期間アプリを開かないユーザー向けの
-- バックストップだけは日次パトロールで別途処理する(Python側)。
--
-- 猶予期間(6時間): ストア課金更新時、grant_credits()に渡すexpires_atを
-- current_period_endぴったりではなく+6時間にする。webhookの遅延は通常
-- 秒〜数分で収まるため、6時間あれば実運用の遅延を十分カバーしつつ、
-- 露出時間を最小限に抑える(3日等の長い猶予は、既存の別バグである
-- UNCANCELLATIONイベントでの同一プラン再付与と組み合わさると、契約解除→
-- 復元を繰り返すだけで満額クレジットが復活し続ける悪用条件を広げてしまう
-- ため採用しない。UNCANCELLATION自体の悪用は今回のスコープ外)。
-- user_subscription_mappings.current_period_endは正確な値のまま変えない
-- (プラン表示・次回更新判定に猶予を漏らさないため)。

CREATE INDEX IF NOT EXISTS credit_grants_expiring_idx
  ON public.credit_grants (user_id, expires_at)
  WHERE remaining_amount > 0;

CREATE OR REPLACE FUNCTION public.materialize_expired_grants(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_expired_amount bigint;
  v_balance_after bigint;
begin
  perform 1 from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and expires_at is not null
      and expires_at <= now()
    for update;

  select coalesce(sum(remaining_amount), 0) into v_expired_amount
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and expires_at is not null
      and expires_at <= now();

  if v_expired_amount <= 0 then
    return;
  end if;

  update credit_grants
    set remaining_amount = 0
    where user_id = p_user_id
      and remaining_amount > 0
      and expires_at is not null
      and expires_at <= now();

  select coalesce(sum(remaining_amount), 0) into v_balance_after
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  insert into credit_transactions (user_id, delta, balance_after, reason)
    values (p_user_id, -v_expired_amount, v_balance_after, 'credit_expired');
end;
$function$;

-- grant_credits: 失効実体化を先頭で呼ぶ以外は元の定義(20260913000000)のまま。
CREATE OR REPLACE FUNCTION public.grant_credits(
  p_user_id uuid,
  p_amount bigint,
  p_source text,
  p_plan_id uuid DEFAULT NULL::uuid,
  p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone
) RETURNS public.credit_grants
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_grant credit_grants;
  v_balance_after bigint;
begin
  perform materialize_expired_grants(p_user_id);

  if p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive, got %', p_amount;
  end if;

  insert into credit_grants (user_id, amount, remaining_amount, source, plan_id, expires_at)
    values (p_user_id, p_amount, p_amount, p_source, p_plan_id, p_expires_at)
    returning * into v_grant;

  select coalesce(sum(remaining_amount), 0) into v_balance_after
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  insert into credit_transactions (user_id, delta, balance_after, reason, related_grant_id)
    values (p_user_id, p_amount, v_balance_after, p_source, v_grant.id);

  return v_grant;
end;
$function$;

-- consume_credits: 失効実体化を先頭で呼ぶ以外は元の定義(20260916000000)のまま。
-- 5引数版のみを残し、削除し忘れていた旧4引数版はこの後dropする。
CREATE OR REPLACE FUNCTION public.consume_credits(
  p_user_id uuid,
  p_amount bigint,
  p_reason text,
  p_job_id uuid DEFAULT NULL::uuid,
  p_metadata jsonb DEFAULT NULL::jsonb
) RETURNS credit_transactions
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_remaining_to_charge bigint := p_amount;
  v_grant record;
  v_balance_after bigint;
  v_shortfall bigint;
  v_metadata jsonb;
  v_tx credit_transactions;
begin
  perform materialize_expired_grants(p_user_id);

  if p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive, got %', p_amount;
  end if;

  perform 1 from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now())
    order by expires_at nulls last, created_at
    for update;

  for v_grant in
    select id, remaining_amount from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now())
      order by expires_at nulls last, created_at
  loop
    exit when v_remaining_to_charge <= 0;

    if v_grant.remaining_amount >= v_remaining_to_charge then
      update credit_grants set remaining_amount = remaining_amount - v_remaining_to_charge
        where id = v_grant.id;
      v_remaining_to_charge := 0;
    else
      update credit_grants set remaining_amount = 0
        where id = v_grant.id;
      v_remaining_to_charge := v_remaining_to_charge - v_grant.remaining_amount;
    end if;
  end loop;

  v_shortfall := v_remaining_to_charge;
  if v_shortfall > 0 then
    raise warning 'consume_credits: user % had insufficient grants, % of % micro-credits unbacked (reason=%)',
      p_user_id, v_shortfall, p_amount, p_reason;
  end if;

  select coalesce(sum(remaining_amount), 0) into v_balance_after
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if v_shortfall > 0 then
    v_metadata := v_metadata || jsonb_build_object('unbacked_shortfall', v_shortfall);
  end if;
  if v_metadata = '{}'::jsonb then
    v_metadata := null;
  end if;

  insert into credit_transactions (user_id, delta, balance_after, reason, related_job_id, metadata)
    values (p_user_id, -p_amount, v_balance_after, p_reason, p_job_id, v_metadata)
    returning * into v_tx;

  return v_tx;
end;
$function$;

-- 削除し忘れていた旧4引数オーバーロード。5引数版と共存すると将来
-- "function is not unique" エラーの温床になるため、この機会に削除する。
DROP FUNCTION IF EXISTS public.consume_credits(uuid, bigint, text, uuid);

-- get_credit_summary: 読み取り専用だが、先頭で失効実体化を走らせることで
-- ユーザーが画面を開くたび(次のポーリング)に失効が即座に台帳へ記録される。
-- 戻り値の形は20260912000000の定義から変更しない。
CREATE OR REPLACE FUNCTION public.get_credit_summary(p_user_id uuid)
 RETURNS TABLE(
   credit_balance bigint,
   monthly_allocation bigint,
   extra_credit_balance bigint,
   has_active_plan boolean,
   current_period_end timestamp with time zone,
   pending_plan_id uuid
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
  perform materialize_expired_grants(p_user_id);

  select coalesce(sum(remaining_amount), 0) into credit_balance
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  select * into v_mapping from user_subscription_mappings
    where user_id = p_user_id and status = 'active'
    limit 1;

  if v_mapping.id is not null then
    has_active_plan := true;
    current_period_end := v_mapping.current_period_end;
    pending_plan_id := v_mapping.pending_plan_id;
    select * into v_plan from subscription_plans where id = v_mapping.plan_id;
    monthly_allocation := v_plan.monthly_credit_amount;
  else
    has_active_plan := false;
  end if;

  select coalesce(sum(remaining_amount), 0) into extra_credit_balance
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now())
      and source not in (
        'subscription_initial', 'subscription_renewal',
        'subscription_initial_store', 'subscription_renewal_store'
      );

  return next;
end;
$function$;

-- renew_subscription (Freeプラン等self_serveの更新経路): 失効実体化を追加し、
-- 付与に6時間の猶予を適用する以外は20260909000000の定義のまま。
CREATE OR REPLACE FUNCTION public.renew_subscription(p_mapping_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
  v_new_period_end timestamp with time zone;
begin
  select * into v_mapping from user_subscription_mappings
    where id = p_mapping_id for update;

  perform materialize_expired_grants(v_mapping.user_id);

  if v_mapping.current_period_end > now() then
    return; -- 冪等
  end if;

  select * into v_plan from subscription_plans where id = v_mapping.plan_id;

  if v_plan.claim_mode <> 'self_serve' then
    return; -- store_purchaseの更新はRevenueCat Webhook経由のみ
  end if;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    update user_subscription_mappings set status = 'expired' where id = p_mapping_id;
    return;
  end if;

  v_new_period_end := v_mapping.current_period_end + (v_plan.billing_interval_months || ' months')::interval;

  perform grant_credits(
    v_mapping.user_id, v_plan.monthly_credit_amount, 'subscription_renewal', v_mapping.plan_id,
    v_new_period_end + interval '6 hours'
  );

  update user_subscription_mappings
    set current_period_start = v_mapping.current_period_end,
        current_period_end = v_new_period_end
    where id = p_mapping_id;
end;
$function$;

-- claim_plan: 失効実体化を追加し、付与に6時間の猶予を適用する以外は
-- 20260918000000の定義のまま。
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
  perform materialize_expired_grants(p_user_id);

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
    v_mapping.current_period_end + interval '6 hours'
  );

  return v_mapping;
end;
$function$;

-- grant_store_subscription_credits: 失効実体化をイベント重複排除の直後、
-- 乗り換え元グラントのゼロ化ロジックより前に追加する。これにより既存の
-- remaining_amount > 0 の集計述語が「本当に生きているグラントだけ」を
-- 拾うようになり、失効済みグラントを二重にリセット計上することがなくなる
-- (個別にexpires_atフィルタを追加する必要はない)。付与には6時間の猶予を
-- 適用する。それ以外は20260914000000の定義のまま。
CREATE OR REPLACE FUNCTION public.grant_store_subscription_credits(
  p_user_id     uuid,
  p_event_id    text,
  p_event_type  text,
  p_product_id  text,
  p_period_end  timestamp with time zone
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_source text;
  v_zeroed_amount bigint;
  v_balance_after bigint;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, p_event_type)
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  perform materialize_expired_grants(p_user_id);

  select * into v_plan from subscription_plans where store_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and status = 'active';

  -- 乗り換え元プランの未消化クレジットをロールオーバーさせない。
  select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
    from credit_grants
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and plan_id is not null
      and remaining_amount > 0;

  if v_zeroed_amount > 0 then
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id <> v_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    select coalesce(sum(remaining_amount), 0) into v_balance_after
      from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now());

    insert into credit_transactions (user_id, delta, balance_after, reason)
      values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_plan_changed');
  end if;

  insert into user_subscription_mappings
      (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end, null)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end,
          pending_plan_id = null;

  v_source := case when p_event_type = 'INITIAL_PURCHASE'
                then 'subscription_initial_store'
                else 'subscription_renewal_store' end;

  -- 同一プランの重複grant防止(サンドボックスの重複/前後したRENEWAL配信対策)。
  select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
    from credit_grants
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store')
      and remaining_amount > 0;

  if v_zeroed_amount > 0 then
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id = v_plan.id
        and source in ('subscription_initial_store', 'subscription_renewal_store')
        and remaining_amount > 0;

    select coalesce(sum(remaining_amount), 0) into v_balance_after
      from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now());

    insert into credit_transactions (user_id, delta, balance_after, reason)
      values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_renewed');
  end if;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end + interval '6 hours');
end;
$function$;

-- expire_store_subscription: 失効実体化を追加する以外は20260914000000の
-- 定義のまま(Freeフォールバックへの付与にも6時間の猶予を適用)。
CREATE OR REPLACE FUNCTION public.expire_store_subscription(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_free_plan subscription_plans;
  v_free_period_end timestamptz;
  v_zeroed_amount bigint;
  v_balance_after bigint;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'EXPIRATION')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  perform materialize_expired_grants(p_user_id);

  select * into v_plan from subscription_plans where store_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';

  select * into v_free_plan from subscription_plans
    where claim_mode = 'self_serve' and disabled_at is null
    order by created_at asc
    limit 1;

  if v_free_plan.id is not null then
    v_free_period_end := now() + (v_free_plan.billing_interval_months || ' months')::interval;

    select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
      from credit_grants
      where user_id = p_user_id
        and plan_id <> v_free_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    if v_zeroed_amount > 0 then
      update credit_grants
        set remaining_amount = 0
        where user_id = p_user_id
          and plan_id <> v_free_plan.id
          and plan_id is not null
          and remaining_amount > 0;

      select coalesce(sum(remaining_amount), 0) into v_balance_after
        from credit_grants
        where user_id = p_user_id
          and remaining_amount > 0
          and (expires_at is null or expires_at > now());

      insert into credit_transactions (user_id, delta, balance_after, reason)
        values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_plan_changed');
    end if;

    insert into user_subscription_mappings
        (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
      values (p_user_id, v_free_plan.id, 'active', now(), v_free_period_end, null)
      on conflict (user_id, plan_id) do update
        set status = 'active',
            current_period_start = now(),
            current_period_end = v_free_period_end,
            pending_plan_id = null;

    perform grant_credits(p_user_id, v_free_plan.monthly_credit_amount, 'subscription_initial', v_free_plan.id, v_free_period_end + interval '6 hours');
  end if;
end;
$function$;
