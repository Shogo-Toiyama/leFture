-- クレジット消費方式の変更(Phase 2): 各タスク完了直後の実コスト課金から、
-- 講義の音声長に応じた固定額をFINALIZE_JOBで1回だけ課金する方式へ移行する。
--
-- 1. lectures.audio_duration_seconds: 音声長を確定させた時点
--    (CHECK_AND_ASSEMBLE=リアルタイム / TRANSCRIBE_MASTER=プレレコ)で書き込み、
--    後段のFINALIZE_JOB(固定クレジット消費)やCORE_EXTRACTION(トピック数上限、
--    後続フェーズで対応)から同じ値を読めるようにする。
ALTER TABLE public.lectures
  ADD COLUMN audio_duration_seconds numeric;

-- 2. consume_credits: p_metadataを追加。reasonは"LECTURE_ANALYSIS"のような
--    短い安定タグのまま残し、「どのLectureにいくら/どのtierで」といった
--    後から増える詳細はmetadata(jsonb)側に積めるようにする。
--    p_metadataを渡さない既存の呼び出し(あれば)はデフォルトNULLで従来通り動く。
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
