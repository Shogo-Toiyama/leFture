-- 契約期間が1か月より長いストア課金(1年のオファーコード等)に、毎月クレジットを補充する。
--
-- これまで: INITIAL_PURCHASE で月額分(例: Max 4,000)を1回だけ付与し、期限は契約終了日。
--   1か月で使い切ると、残りの11か月はクレジットが無い。
--
-- 方針(通常の月額更新と同じ扱い):
--   * 補充日 = 「最後の通常付与日」から 1か月, 2か月, ... 後。繰り越しなし
--     (そのプランのストア付与の残りを0にしてから、月額分を付与)。
--   * 「最後の通常付与」= source が subscription_initial_store / subscription_renewal_store の
--     最新の付与のうち、補充で作ったもの(metadata.refill)を除いたもの。
--     補充分も source は subscription_renewal_store のままにして、既存の
--     ゼロ化(RENEWAL・プラン変更)・TRANSFER の対象に自動で入るようにしている。
--   * 長い期間 = 現在の契約終了日 - 最後の通常付与日 > 40日。
--     (current_period_start は更新しても進まないので使えない。月額契約の誤判定を防ぐ)
--   * 補充は (mapping, 付与日, 何か月目) ごとに1回(revenuecat_webhook_events で冪等)。
--   * 既存データは「次の月から」: 補充日が p_first_cycle_not_before(既定 2026-11-11)より前のものは
--     補充しない(適用前に過ぎた補充日を遡って付与しない)。
--   * 付与の期限は 契約終了日 + store_credit_backstop()(通常の付与と同じ)。
--   * 実行はパトロール(main.py)が定期的に呼ぶ。1回で最大 p_limit 人。
--   * 補充したら billing_webhook_log(source='reconcile', event_type='REFILL')に1行残す。

CREATE OR REPLACE FUNCTION public.refill_long_period_store_credits(
  p_limit integer DEFAULT 50,
  p_first_cycle_not_before timestamp with time zone DEFAULT '2026-11-11T00:00:00Z'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  c record;
  v_k integer;
  v_due timestamptz;
  v_event_id text;
  v_zeroed bigint;
  v_balance_after bigint;
  v_grant credit_grants;
  v_candidates integer := 0;
  v_done jsonb := '[]'::jsonb;
begin
  for c in
    select m.id as mapping_id, m.user_id, m.plan_id, m.current_period_end,
           p.monthly_credit_amount, p.name as plan_name,
           (select max(g.created_at) from credit_grants g
             where g.user_id = m.user_id and g.plan_id = m.plan_id
               and g.source in ('subscription_initial_store', 'subscription_renewal_store')
               and coalesce((g.metadata->>'refill')::boolean, false) = false) as anchor
      from user_subscription_mappings m
      join subscription_plans p on p.id = m.plan_id
     where m.status = 'active'
       and p.claim_mode = 'store_purchase'
       and m.current_period_end > now()
  loop
    if c.anchor is null or c.current_period_end - c.anchor <= interval '40 days' then
      continue;
    end if;

    v_k := (extract(year from age(now(), c.anchor)) * 12 + extract(month from age(now(), c.anchor)))::integer;
    if v_k < 1 then
      continue;
    end if;
    v_due := c.anchor + make_interval(months => v_k);
    if v_due < p_first_cycle_not_before then
      continue;
    end if;

    v_candidates := v_candidates + 1;
    exit when jsonb_array_length(v_done) >= p_limit;

    v_event_id := 'refill:' || c.mapping_id || ':' || extract(epoch from c.anchor)::bigint || ':' || v_k;
    insert into revenuecat_webhook_events (event_id, event_type)
      values (v_event_id, 'REFILL')
      on conflict (event_id) do nothing;
    if not found then
      continue;
    end if;

    perform materialize_expired_grants(c.user_id);

    select coalesce(sum(remaining_amount), 0) into v_zeroed
      from credit_grants
      where user_id = c.user_id and plan_id = c.plan_id
        and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
        and remaining_amount > 0;

    if v_zeroed > 0 then
      update credit_grants set remaining_amount = 0
        where user_id = c.user_id and plan_id = c.plan_id
          and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
          and remaining_amount > 0;

      select coalesce(sum(remaining_amount), 0) into v_balance_after
        from credit_grants
        where user_id = c.user_id and remaining_amount > 0
          and (expires_at is null or expires_at > now());

      insert into credit_transactions (user_id, delta, balance_after, reason)
        values (c.user_id, -v_zeroed, v_balance_after, 'credit_reset_renewed');
    end if;

    v_grant := grant_credits(c.user_id, c.monthly_credit_amount, 'subscription_renewal_store', c.plan_id,
                             c.current_period_end + public.store_credit_backstop());
    update credit_grants
      set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('refill', true, 'refill_month', v_k)
      where id = v_grant.id;

    insert into billing_webhook_log (source, event_id, event_type, user_id, app_user_id, product_id,
                                     expiration_at, status, result, processed_at)
      values ('reconcile', v_event_id, 'REFILL', c.user_id, c.user_id::text, null,
              c.current_period_end, 'processed',
              jsonb_build_object('plan', c.plan_name, 'refill_month', v_k, 'zeroed_micro', v_zeroed,
                                 'granted_micro', c.monthly_credit_amount),
              now());

    v_done := v_done || jsonb_build_object('user_id', c.user_id, 'plan', c.plan_name, 'refill_month', v_k);
  end loop;

  return jsonb_build_object('candidates', v_candidates, 'refilled', v_done);
end;
$function$;

REVOKE ALL ON FUNCTION public.refill_long_period_store_credits(integer, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refill_long_period_store_credits(integer, timestamp with time zone) TO service_role;
