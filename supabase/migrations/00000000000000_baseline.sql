--
-- PostgreSQL database dump
--
-- pg_dumpの元出力から、この場では不要/有害な2箇所を手作業で除去している:
-- 1. \restrict / \unrestrict (末尾) — psql専用のメタコマンドで生SQLとしては
--    無効。supabase db push等はpsqlを介さず直接SQLを実行するため残すとエラーになる。
-- 2. CREATE SCHEMA public — publicスキーマは新規のPostgresに最初から存在する
--    ため、ローカルのsupabase db reset等で実行すると「既に存在する」エラーになる。

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: user_subscription_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_subscription_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    status text,
    current_period_start timestamp with time zone,
    current_period_end timestamp with time zone,
    metadata jsonb
);


--
-- Name: claim_plan(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_plan(p_user_id uuid, p_plan_id uuid) RETURNS public.user_subscription_mappings
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_plan subscription_plans;
  v_mapping user_subscription_mappings;
  v_credit_expires_at timestamptz;
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

  -- (user_id, plan_id)のユニーク制約が最終防波堤。ここでの事前チェックは
  -- わかりやすいエラーメッセージを返すためだけのもの(実際の排他性はDB制約が担保)。
  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id and plan_id = p_plan_id
  ) then
    raise exception 'plan_already_claimed';
  end if;

  insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end)
    values (
      p_user_id, p_plan_id, 'active', now(),
      now() + (v_plan.billing_interval_months || ' months')::interval
    )
    returning * into v_mapping;

  v_credit_expires_at := case
    when v_plan.credit_expiry_days is not null then now() + (v_plan.credit_expiry_days || ' days')::interval
    else null
  end;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, 'subscription_initial', p_plan_id, v_credit_expires_at);

  return v_mapping;
end;
$$;


--
-- Name: credit_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    delta bigint NOT NULL,
    balance_after bigint NOT NULL,
    reason text,
    related_job_id uuid,
    related_grant_id uuid,
    metadata jsonb
);


--
-- Name: consume_credits(uuid, bigint, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_credits(p_user_id uuid, p_amount bigint, p_reason text, p_job_id uuid DEFAULT NULL::uuid) RETURNS public.credit_transactions
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_available bigint;
  v_remaining_to_charge bigint := p_amount;
  v_grant record;
  v_balance_after bigint;
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

  select coalesce(sum(remaining_amount), 0) into v_available
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

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

  v_balance_after := v_available - p_amount;

  insert into credit_transactions (user_id, delta, balance_after, reason, related_job_id)
    values (p_user_id, -p_amount, v_balance_after, p_reason, p_job_id)
    returning * into v_tx;

  insert into user_credit_balances (user_id, credit_balance, updated_at)
    values (p_user_id, v_balance_after, now())
    on conflict (user_id) do update set credit_balance = excluded.credit_balance, updated_at = now();

  return v_tx;
end;
$$;


--
-- Name: get_credit_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_credit_summary(p_user_id uuid) RETURNS TABLE(credit_balance bigint, monthly_allocation bigint, extra_credit_balance bigint, has_active_plan boolean, current_period_end timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
  select cb.credit_balance into credit_balance
    from user_credit_balances cb where cb.user_id = p_user_id;

  select * into v_mapping from user_subscription_mappings
    where user_id = p_user_id and status = 'active'
    limit 1;

  if v_mapping.id is not null then
    has_active_plan := true;
    current_period_end := v_mapping.current_period_end;
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
      and source not in ('subscription_initial', 'subscription_renewal');

  return next;
end;
$$;


--
-- Name: credit_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    amount bigint NOT NULL,
    remaining_amount bigint NOT NULL,
    source text,
    plan_id uuid,
    expires_at timestamp with time zone,
    metadata jsonb
);


--
-- Name: grant_credits(uuid, bigint, text, uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grant_credits(p_user_id uuid, p_amount bigint, p_source text, p_plan_id uuid DEFAULT NULL::uuid, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS public.credit_grants
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_grant credit_grants;
  v_balance_after bigint;
begin
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

  insert into user_credit_balances (user_id, credit_balance, updated_at)
    values (p_user_id, v_balance_after, now())
    on conflict (user_id) do update set credit_balance = excluded.credit_balance, updated_at = now();

  return v_grant;
end;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  inserted_username text;
  inserted_avatar_url text;
begin
  -- ① Username の決定ロジック
  -- メタデータからアプリで指定された 'username' または 'display_name' のみを探す
  -- (ソーシャルアカウントの本名である 'full_name' や 'name' は一切使用しない)
  inserted_username := coalesce(
    new.raw_user_meta_data->>'username',
    new.raw_user_meta_data->>'display_name'
  );

  -- ② アバターURL の決定ロジック
  inserted_avatar_url := coalesce(
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'avatar_url_https',
    new.raw_user_meta_data->>'picture'
  );

  -- ③ user_profiles テーブルへのデータ挿入 (CONFLICT 時は既存値を保持)
  insert into public.user_profiles (
    id, 
    username, 
    avatar_url
  )
  values (
    new.id,
    inserted_username,
    inserted_avatar_url
  )
  on conflict (id) do update set
    username = coalesce(user_profiles.username, excluded.username),
    avatar_url = coalesce(user_profiles.avatar_url, excluded.avatar_url);

  return new;
end;
$$;


--
-- Name: renew_subscription(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.renew_subscription(p_mapping_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
  select * into v_mapping from user_subscription_mappings
    where id = p_mapping_id for update;

  if v_mapping.current_period_end > now() then
    return; -- 冪等
  end if;

  select * into v_plan from subscription_plans where id = v_mapping.plan_id;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    update user_subscription_mappings set status = 'expired' where id = p_mapping_id;
    return;
  end if;

  -- 月次クレジットはロールオーバーさせない。同じプランのsubscription_initial/
  -- subscription_renewal由来の未消化分だけを失効させる。store_purchase等の
  -- 追加クレジット(source違い)はここでは一切触らない。
  update credit_grants
    set remaining_amount = 0
    where user_id = v_mapping.user_id
      and plan_id = v_mapping.plan_id
      and source in ('subscription_initial', 'subscription_renewal')
      and remaining_amount > 0;

  perform grant_credits(
    v_mapping.user_id, v_plan.monthly_credit_amount, 'subscription_renewal', v_mapping.plan_id,
    case when v_plan.credit_expiry_days is not null
      then now() + (v_plan.credit_expiry_days || ' days')::interval
      else null
    end
  );

  update user_subscription_mappings
    set current_period_start = now(),
        current_period_end = now() + (v_plan.billing_interval_months || ' months')::interval
    where id = p_mapping_id;
end;
$$;


--
-- Name: set_folder_sort_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_folder_sort_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
  next_order integer;
begin
  if new.sort_order is null or new.sort_order = 0 then
    select coalesce(max(sort_order), 0) + 1
      into next_order
    from public.lecture_folders
    where user_id = auth.uid()
      and (
        (parent_id is null and new.parent_id is null)
        or parent_id = new.parent_id
      );

    new.sort_order := next_order;
  end if;

  return new;
end;$$;


--
-- Name: set_lecture_sort_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_lecture_sort_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
  next_order integer;
  effective_user uuid;
  should_calc boolean := false;
begin
  -- user_id が来てなければ auth.uid() を使う
  effective_user := coalesce(new.user_id, auth.uid());

  -- 条件A: 新規作成 (INSERT) で、sort_order が未指定の場合
  if (TG_OP = 'INSERT') and (new.sort_order is null or new.sort_order = 0) then
    should_calc := true;
  end if;

  -- 条件B: 更新 (UPDATE) で、コースID（旧フォルダID）が変わった場合
  if (TG_OP = 'UPDATE') and (new.course_id is distinct from old.course_id) then
    should_calc := true;
  end if;

  -- どちらかの条件に当てはまったら、新しい sort_order を計算する
  if should_calc then
    select coalesce(max(sort_order), 0) + 1
      into next_order
    from public.lectures
    where user_id = effective_user
      -- 移動先のコース内で最大値を探す
      and (course_id is not distinct from new.course_id);

    new.sort_order := next_order;
  end if;

  return new;
end;$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    user_id uuid,
    lecture_id uuid,
    type text,
    title text,
    description text,
    location text,
    start_sid text,
    end_sid text,
    related_topic_title text,
    datetime_parameters jsonb,
    completed_at timestamp with time zone,
    metadata jsonb,
    deleted_at timestamp with time zone
);


--
-- Name: app_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_config (
    id integer DEFAULT 1 NOT NULL,
    maintenance boolean DEFAULT false NOT NULL,
    maintenance_message text,
    min_build_number integer DEFAULT 0 NOT NULL,
    update_message text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT app_config_singleton CHECK ((id = 1))
);


--
-- Name: app_transmissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_transmissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category text,
    title text NOT NULL,
    content text NOT NULL,
    image_path text,
    action_label text DEFAULT 'Got it'::text,
    action_url text,
    priority integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    published_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: course_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_attributes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    attribute_type text,
    attribute_name text,
    metadata jsonb,
    user_id uuid,
    deleted_at timestamp with time zone
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    school_id uuid,
    year_id uuid,
    term_id uuid,
    subject_id uuid,
    course_code text,
    course_title text,
    summary text,
    metadata jsonb,
    user_id uuid,
    professor uuid
);


--
-- Name: deep_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deep_notes (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid,
    lecture_id uuid,
    topic_number smallint,
    note_contents text,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    metadata jsonb
);


--
-- Name: fun_facts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fun_facts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid,
    lecture_id uuid,
    title text,
    hook text,
    body text,
    metadata jsonb,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: keywords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.keywords (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    lecture_id uuid,
    topic_number smallint,
    keyword text,
    definition text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    metadata jsonb
);


--
-- Name: lecture_moments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lecture_moments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    user_id uuid,
    lecture_id uuid,
    moment_type text,
    note_text text,
    timestamp_sec smallint
);


--
-- Name: lecture_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lecture_topics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    user_id uuid,
    lecture_id uuid,
    index smallint,
    topic_title text,
    topic_type text,
    summary text,
    start_sid text,
    end_sid text,
    image_path text,
    deleted_at timestamp with time zone
);


--
-- Name: lecture_transcripts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lecture_transcripts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lecture_id uuid,
    chunk_index integer NOT NULL,
    storage_path text NOT NULL,
    text_stt text,
    confidence double precision,
    status text DEFAULT 'PENDING'::text,
    created_at timestamp with time zone DEFAULT now(),
    segments_stt jsonb,
    audio_duration real,
    start_time real,
    text_reviewed text,
    segments_reviewed jsonb,
    billing_records jsonb
);


--
-- Name: lectures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lectures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    course_id uuid DEFAULT gen_random_uuid(),
    title text,
    lecture_datetime timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sort_order smallint NOT NULL,
    title_generated text,
    summary text,
    audio_path text,
    metadata jsonb,
    deleted_at timestamp with time zone,
    recording_language text,
    display_language text
);


--
-- Name: legal_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_documents (
    slug text NOT NULL,
    locale text DEFAULT 'en'::text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    title text NOT NULL,
    content_markdown text NOT NULL,
    effective_date date NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    region text DEFAULT 'us'::text NOT NULL
);


--
-- Name: processing_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processing_jobs (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    lecture_id uuid NOT NULL,
    expected_chunks integer NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL
);


--
-- Name: processing_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processing_tasks (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    job_id uuid NOT NULL,
    task_type text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    dependencies jsonb DEFAULT '[]'::jsonb NOT NULL,
    result_payload jsonb,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: review_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid,
    lecture_id uuid,
    topic_number smallint,
    card_content jsonb,
    card_type text,
    title text,
    hero_emoji text,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    metadata jsonb
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text,
    monthly_credit_amount bigint,
    credit_expiry_days smallint,
    price_usd numeric,
    updated_at timestamp with time zone DEFAULT now(),
    disabled_at timestamp with time zone,
    metadata jsonb,
    claim_mode text NOT NULL,
    billing_interval_months smallint DEFAULT '1'::smallint NOT NULL
);


--
-- Name: support_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_code text NOT NULL,
    user_id uuid,
    user_email text NOT NULL,
    category text NOT NULL,
    message text NOT NULL,
    attachment_urls text[] DEFAULT '{}'::text[],
    device_info jsonb DEFAULT '{}'::jsonb,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: topic_maps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.topic_maps (
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    course_id uuid,
    map jsonb,
    metadata jsonb,
    user_id uuid,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone,
    is_stale boolean DEFAULT false NOT NULL,
    stale_since timestamp with time zone,
    pending_removals jsonb DEFAULT '[]'::jsonb NOT NULL,
    pending_additions jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: usage_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    job_id uuid,
    task_id uuid,
    cost_usd numeric NOT NULL,
    cost_breakdown jsonb,
    metadata jsonb,
    micro_credits_charged bigint NOT NULL
);


--
-- Name: user_credit_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_credit_balances (
    user_id uuid NOT NULL,
    credit_balance bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    username text,
    avatar_url text,
    bio text,
    interests text,
    future_goals text,
    metadata jsonb,
    deleted_at timestamp with time zone,
    course_view_template text[]
);


--
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (id);


--
-- Name: app_transmissions app_transmissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_transmissions
    ADD CONSTRAINT app_transmissions_pkey PRIMARY KEY (id);


--
-- Name: course_attributes course_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_attributes
    ADD CONSTRAINT course_attributes_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: credit_grants credit_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_grants
    ADD CONSTRAINT credit_grants_pkey PRIMARY KEY (id);


--
-- Name: credit_transactions credit_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_transactions
    ADD CONSTRAINT credit_transactions_pkey PRIMARY KEY (id);


--
-- Name: deep_notes deep_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_notes
    ADD CONSTRAINT deep_notes_pkey PRIMARY KEY (id);


--
-- Name: fun_facts fun_facts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fun_facts
    ADD CONSTRAINT fun_facts_pkey PRIMARY KEY (id);


--
-- Name: keywords keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keywords
    ADD CONSTRAINT keywords_pkey PRIMARY KEY (id);


--
-- Name: lecture_moments lecture_moments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_moments
    ADD CONSTRAINT lecture_moments_pkey PRIMARY KEY (id);


--
-- Name: lecture_topics lecture_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_topics
    ADD CONSTRAINT lecture_topics_pkey PRIMARY KEY (id);


--
-- Name: lecture_transcripts lecture_transcripts_lecture_chunk_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_transcripts
    ADD CONSTRAINT lecture_transcripts_lecture_chunk_unique UNIQUE (lecture_id, chunk_index);


--
-- Name: lecture_transcripts lecture_transcripts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_transcripts
    ADD CONSTRAINT lecture_transcripts_pkey PRIMARY KEY (id);


--
-- Name: lectures lectures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lectures
    ADD CONSTRAINT lectures_pkey PRIMARY KEY (id);


--
-- Name: legal_documents legal_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_documents
    ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (slug, locale, region);


--
-- Name: processing_jobs processing_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_jobs
    ADD CONSTRAINT processing_jobs_pkey PRIMARY KEY (id);


--
-- Name: processing_tasks processing_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_tasks
    ADD CONSTRAINT processing_tasks_pkey PRIMARY KEY (id);


--
-- Name: user_profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: review_cards review_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_cards
    ADD CONSTRAINT review_cards_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: support_tickets support_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_pkey PRIMARY KEY (id);


--
-- Name: support_tickets support_tickets_ticket_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_ticket_code_key UNIQUE (ticket_code);


--
-- Name: topic_maps topic_maps_course_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_maps
    ADD CONSTRAINT topic_maps_course_id_key UNIQUE (course_id);


--
-- Name: topic_maps topic_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_maps
    ADD CONSTRAINT topic_maps_pkey PRIMARY KEY (id);


--
-- Name: usage_records usage_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_records
    ADD CONSTRAINT usage_records_pkey PRIMARY KEY (id);


--
-- Name: user_credit_balances user_credit_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_credit_balances
    ADD CONSTRAINT user_credit_balances_pkey PRIMARY KEY (user_id);


--
-- Name: user_subscription_mappings user_subscription_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscription_mappings
    ADD CONSTRAINT user_subscription_mappings_pkey PRIMARY KEY (id);


--
-- Name: idx_app_transmissions_active_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_app_transmissions_active_published ON public.app_transmissions USING btree (is_active, published_at DESC);


--
-- Name: idx_topic_maps_stale_since; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_topic_maps_stale_since ON public.topic_maps USING btree (stale_since) WHERE (is_stale = true);


--
-- Name: user_subscription_mappings_user_plan_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_subscription_mappings_user_plan_uidx ON public.user_subscription_mappings USING btree (user_id, plan_id);


--
-- Name: processing_tasks Trigger Orchestrator; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "Trigger Orchestrator" AFTER INSERT OR UPDATE ON public.processing_tasks FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://lefture-511705914929.us-west1.run.app/webhook/orchestrator', 'POST', '{"x-webhook-secret":"Yvygk@-9pQvwW%rG%14hQq1h"}', '{}', '10000');


--
-- Name: lectures trg_lecture_sort_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lecture_sort_order BEFORE INSERT OR UPDATE ON public.lectures FOR EACH ROW EXECUTE FUNCTION public.set_lecture_sort_order();


--
-- Name: announcements trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.announcements FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: app_config trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.app_config FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: course_attributes trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.course_attributes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: courses trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.courses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: deep_notes trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.deep_notes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: fun_facts trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.fun_facts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: keywords trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.keywords FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: lecture_moments trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.lecture_moments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: lecture_topics trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.lecture_topics FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: lectures trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.lectures FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: legal_documents trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.legal_documents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: processing_jobs trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.processing_jobs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: processing_tasks trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.processing_tasks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: review_cards trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.review_cards FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: support_tickets trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: topic_maps trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.topic_maps FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: user_profiles trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: announcements announcements_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: announcements announcements_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: course_attributes course_attributes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_attributes
    ADD CONSTRAINT course_attributes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: courses courses_professor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_professor_fkey FOREIGN KEY (professor) REFERENCES public.course_attributes(id);


--
-- Name: courses courses_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.course_attributes(id);


--
-- Name: courses courses_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.course_attributes(id);


--
-- Name: courses courses_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.course_attributes(id);


--
-- Name: courses courses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: courses courses_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_year_id_fkey FOREIGN KEY (year_id) REFERENCES public.course_attributes(id);


--
-- Name: credit_grants credit_grants_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_grants
    ADD CONSTRAINT credit_grants_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id) ON DELETE SET NULL;


--
-- Name: credit_grants credit_grants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_grants
    ADD CONSTRAINT credit_grants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: credit_transactions credit_transactions_related_grant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_transactions
    ADD CONSTRAINT credit_transactions_related_grant_id_fkey FOREIGN KEY (related_grant_id) REFERENCES public.credit_grants(id) ON DELETE SET NULL;


--
-- Name: credit_transactions credit_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_transactions
    ADD CONSTRAINT credit_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: deep_notes deep_notes_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_notes
    ADD CONSTRAINT deep_notes_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id);


--
-- Name: deep_notes deep_notes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_notes
    ADD CONSTRAINT deep_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: fun_facts fun_facts_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fun_facts
    ADD CONSTRAINT fun_facts_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: fun_facts fun_facts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fun_facts
    ADD CONSTRAINT fun_facts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: keywords keywords_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keywords
    ADD CONSTRAINT keywords_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: keywords keywords_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keywords
    ADD CONSTRAINT keywords_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: lecture_moments lecture_moments_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_moments
    ADD CONSTRAINT lecture_moments_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: lecture_moments lecture_moments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_moments
    ADD CONSTRAINT lecture_moments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: lecture_topics lecture_topics_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_topics
    ADD CONSTRAINT lecture_topics_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: lecture_topics lecture_topics_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_topics
    ADD CONSTRAINT lecture_topics_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: lecture_transcripts lecture_transcripts_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lecture_transcripts
    ADD CONSTRAINT lecture_transcripts_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: lectures lectures_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lectures
    ADD CONSTRAINT lectures_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: lectures lectures_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lectures
    ADD CONSTRAINT lectures_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id);


--
-- Name: processing_jobs processing_jobs_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_jobs
    ADD CONSTRAINT processing_jobs_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id) ON DELETE CASCADE;


--
-- Name: processing_jobs processing_jobs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_jobs
    ADD CONSTRAINT processing_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: processing_tasks processing_tasks_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_tasks
    ADD CONSTRAINT processing_tasks_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.processing_jobs(id) ON DELETE CASCADE;


--
-- Name: user_profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: review_cards review_cards_lecture_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_cards
    ADD CONSTRAINT review_cards_lecture_id_fkey FOREIGN KEY (lecture_id) REFERENCES public.lectures(id);


--
-- Name: review_cards review_cards_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_cards
    ADD CONSTRAINT review_cards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: support_tickets support_tickets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: topic_maps topic_maps_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_maps
    ADD CONSTRAINT topic_maps_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: topic_maps topic_maps_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_maps
    ADD CONSTRAINT topic_maps_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: usage_records usage_records_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_records
    ADD CONSTRAINT usage_records_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: user_credit_balances user_credit_balances_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_credit_balances
    ADD CONSTRAINT user_credit_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: user_subscription_mappings user_subscription_mappings_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscription_mappings
    ADD CONSTRAINT user_subscription_mappings_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id);


--
-- Name: user_subscription_mappings user_subscription_mappings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_subscription_mappings
    ADD CONSTRAINT user_subscription_mappings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: app_config Allow public read access for app_config; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read access for app_config" ON public.app_config FOR SELECT USING (true);


--
-- Name: legal_documents Allow public read access for legal_documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read access for legal_documents" ON public.legal_documents FOR SELECT USING (true);


--
-- Name: app_transmissions Allow public read access to active transmissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read access to active transmissions" ON public.app_transmissions FOR SELECT USING (((is_active = true) AND (published_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now()))));


--
-- Name: support_tickets Users can insert their own tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own tickets" ON public.support_tickets FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_transcripts Users can insert their own transcripts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own transcripts" ON public.lecture_transcripts FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.lectures
  WHERE ((lectures.id = lecture_transcripts.lecture_id) AND (lectures.user_id = auth.uid())))));


--
-- Name: lecture_transcripts Users can select their own transcripts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can select their own transcripts" ON public.lecture_transcripts FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.lectures
  WHERE ((lectures.id = lecture_transcripts.lecture_id) AND (lectures.user_id = auth.uid())))));


--
-- Name: support_tickets Users can view their own tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own tickets" ON public.support_tickets FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: announcements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

--
-- Name: announcements announcements_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_delete_own ON public.announcements FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: announcements announcements_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_insert_own ON public.announcements FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: announcements announcements_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_select_own ON public.announcements FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: announcements announcements_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_update_own ON public.announcements FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: app_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

--
-- Name: app_transmissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_transmissions ENABLE ROW LEVEL SECURITY;

--
-- Name: course_attributes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.course_attributes ENABLE ROW LEVEL SECURITY;

--
-- Name: course_attributes course_attributes_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_attributes_delete_own ON public.course_attributes FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: course_attributes course_attributes_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_attributes_insert_own ON public.course_attributes FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: course_attributes course_attributes_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_attributes_select_own ON public.course_attributes FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: course_attributes course_attributes_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_attributes_update_own ON public.course_attributes FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: courses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

--
-- Name: courses courses_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY courses_delete_own ON public.courses FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: courses courses_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY courses_insert_own ON public.courses FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: courses courses_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY courses_select_own ON public.courses FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: courses courses_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY courses_update_own ON public.courses FOR UPDATE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: credit_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: deep_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deep_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: deep_notes deep_notes_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY deep_notes_delete_own ON public.deep_notes FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: deep_notes deep_notes_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY deep_notes_insert_own ON public.deep_notes FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: deep_notes deep_notes_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY deep_notes_select_own ON public.deep_notes FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: deep_notes deep_notes_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY deep_notes_update_own ON public.deep_notes FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: fun_facts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fun_facts ENABLE ROW LEVEL SECURITY;

--
-- Name: fun_facts fun_facts_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fun_facts_delete_own ON public.fun_facts FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: fun_facts fun_facts_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fun_facts_insert_own ON public.fun_facts FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: fun_facts fun_facts_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fun_facts_select_own ON public.fun_facts FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: fun_facts fun_facts_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fun_facts_update_own ON public.fun_facts FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: processing_jobs jobs_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jobs_insert_own ON public.processing_jobs FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: processing_jobs jobs_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jobs_select_own ON public.processing_jobs FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: keywords; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.keywords ENABLE ROW LEVEL SECURITY;

--
-- Name: keywords keywords_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY keywords_delete_own ON public.keywords FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: keywords keywords_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY keywords_insert_own ON public.keywords FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: keywords keywords_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY keywords_select_own ON public.keywords FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: keywords keywords_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY keywords_update_own ON public.keywords FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_moments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lecture_moments ENABLE ROW LEVEL SECURITY;

--
-- Name: lecture_moments lecture_moments_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_moments_delete_own ON public.lecture_moments FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: lecture_moments lecture_moments_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_moments_insert_own ON public.lecture_moments FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_moments lecture_moments_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_moments_select_own ON public.lecture_moments FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: lecture_moments lecture_moments_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_moments_update_own ON public.lecture_moments FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_topics; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lecture_topics ENABLE ROW LEVEL SECURITY;

--
-- Name: lecture_topics lecture_topics_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_topics_delete_own ON public.lecture_topics FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: lecture_topics lecture_topics_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_topics_insert_own ON public.lecture_topics FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_topics lecture_topics_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_topics_select_own ON public.lecture_topics FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: lecture_topics lecture_topics_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lecture_topics_update_own ON public.lecture_topics FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: lecture_transcripts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lecture_transcripts ENABLE ROW LEVEL SECURITY;

--
-- Name: lectures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lectures ENABLE ROW LEVEL SECURITY;

--
-- Name: lectures lectures_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lectures_delete_own ON public.lectures FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: lectures lectures_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lectures_insert_own ON public.lectures FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: lectures lectures_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lectures_select_own ON public.lectures FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: lectures lectures_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lectures_update_own ON public.lectures FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: legal_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: processing_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.processing_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: processing_tasks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.processing_tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: review_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.review_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: review_cards review_cards_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY review_cards_delete_own ON public.review_cards FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: review_cards review_cards_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY review_cards_insert_own ON public.review_cards FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: review_cards review_cards_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY review_cards_select_own ON public.review_cards FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: review_cards review_cards_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY review_cards_update_own ON public.review_cards FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: subscription_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: support_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: processing_tasks tasks_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_insert_own ON public.processing_tasks FOR INSERT WITH CHECK ((job_id IN ( SELECT processing_jobs.id
   FROM public.processing_jobs
  WHERE (processing_jobs.user_id = auth.uid()))));


--
-- Name: processing_tasks tasks_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_select_own ON public.processing_tasks FOR SELECT USING ((job_id IN ( SELECT processing_jobs.id
   FROM public.processing_jobs
  WHERE (processing_jobs.user_id = auth.uid()))));


--
-- Name: topic_maps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.topic_maps ENABLE ROW LEVEL SECURITY;

--
-- Name: topic_maps topic_maps_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY topic_maps_delete_own ON public.topic_maps FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: topic_maps topic_maps_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY topic_maps_insert_own ON public.topic_maps FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: topic_maps topic_maps_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY topic_maps_select_own ON public.topic_maps FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: topic_maps topic_maps_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY topic_maps_update_own ON public.topic_maps FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: usage_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.usage_records ENABLE ROW LEVEL SECURITY;

--
-- Name: user_credit_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_credit_balances ENABLE ROW LEVEL SECURITY;

--
-- Name: user_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_profiles user_profiles_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_delete_own ON public.user_profiles FOR DELETE TO authenticated USING ((auth.uid() = id));


--
-- Name: user_profiles user_profiles_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_insert_own ON public.user_profiles FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));


--
-- Name: user_profiles user_profiles_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_select_own ON public.user_profiles FOR SELECT TO authenticated USING ((auth.uid() = id));


--
-- Name: user_profiles user_profiles_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_update_own ON public.user_profiles FOR UPDATE TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));


--
-- Name: user_subscription_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_subscription_mappings ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

