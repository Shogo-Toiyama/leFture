-- ============================================================
-- 自分像プロフィール(docs/chatbot_context_and_retrieval_roadmap.md 9章)
--
--   1層 表紙       : user_profiles(既存)+ 欄ごとの書き手 + 書き直し案
--   2層 自分像     : profile_categories / profile_items(+ 根拠 / 書き直し履歴)
--   4層 観察メモ   : profile_observations(本人には見せない)
--   AIチャット設定 : ai_memos(覚え書き) / profile_hypotheses(確かめたい仮説)
--   残したくない   : profile_blocked_areas(分野だけ。中身は持たない)
--   処理の状態     : profile_extraction_state(ユーザーごと)、chat_threads の観察位置
--
-- 書き込みはすべてバックエンド(service_role)から行う。本人の操作(違う・直す・
-- 残したくない・確認トレイ・書き直し案)もバックエンドのAPIを通すので、
-- authenticated 向けには SELECT のポリシーだけを置く。観察メモと仮説は
-- 本人の画面に出さないので、SELECT のポリシーも置かない。
-- ============================================================


-- ------------------------------------------------------------
-- 1. カテゴリ(2層の棚)。固定せず、まとめ役が必要なものだけ作る。親子は2段まで
--    (段数はバックエンドで検証する)
-- ------------------------------------------------------------
CREATE TABLE public.profile_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    kind text NOT NULL,
    parent_id uuid,
    -- 整理役が統合したときの行き先(統合された側は表示しない)
    merged_into uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.profile_categories
    ADD CONSTRAINT profile_categories_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_categories
    ADD CONSTRAINT profile_categories_kind_check CHECK (kind IN ('trait', 'record'));
ALTER TABLE ONLY public.profile_categories
    ADD CONSTRAINT profile_categories_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_categories
    ADD CONSTRAINT profile_categories_parent_id_fkey
    FOREIGN KEY (parent_id) REFERENCES public.profile_categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.profile_categories
    ADD CONSTRAINT profile_categories_merged_into_fkey
    FOREIGN KEY (merged_into) REFERENCES public.profile_categories(id) ON DELETE SET NULL;

CREATE INDEX idx_profile_categories_user ON public.profile_categories (user_id);

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.profile_categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profile_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own profile categories"
    ON public.profile_categories FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 2. 観察メモ(4層)。観察役が1スレッドの差分から書く。一般化はしない
-- ------------------------------------------------------------
CREATE TABLE public.profile_observations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    -- 根拠にした本人の発言(chat_messages.id)
    source_message_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    observed_at date NOT NULL,
    occurred_at date,
    ends_at date,
    note text NOT NULL,
    topic text DEFAULT ''::text NOT NULL,
    -- 惹かれた点。分からなければNULL(推測で埋めない)
    hook text,
    caveat text,
    quote text,
    reaction text NOT NULL,
    initiative text NOT NULL,
    certainty text NOT NULL,
    context text NOT NULL,
    kind_hint text NOT NULL,
    sensitive text DEFAULT 'none'::text NOT NULL,
    -- open: まだ項目に使われていない / used: 項目の根拠になった / discounted: 根拠の項目が「違う」と言われた
    status text DEFAULT 'open'::text NOT NULL,
    -- まとめ役に「新しい観察」として渡し終えた時刻(NULLならまだ)
    consolidated_at timestamp with time zone,
    -- 惹かれた点(無ければnote)だけを埋め込む。話題で束ねないため
    embedding extensions.vector(768),
    embedding_model text,
    model text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    -- スレッドの論理削除に合わせて立てる(スレッドを戻せば外す)
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_reaction_check CHECK (reaction IN ('strong', 'moderate', 'mild', 'neutral'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_initiative_check CHECK (initiative IN ('user', 'ai'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_certainty_check CHECK (certainty IN ('stated', 'strong_implicit', 'inferred'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_context_check
    CHECK (context IN ('casual', 'lecture_review', 'exam_prep', 'consult', 'onboarding'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_kind_hint_check
    CHECK (kind_hint IN ('trait', 'future', 'record', 'answer_style', 'situation'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_sensitive_check
    CHECK (sensitive IN ('none', 'religion', 'health', 'sexuality', 'politics', 'ethnicity'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_status_check CHECK (status IN ('open', 'used', 'discounted'));
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_observations
    ADD CONSTRAINT profile_observations_thread_id_fkey
    FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE CASCADE;

-- まとめ役の「まだ渡していない観察」と、近い観察の検索はどちらも本人の生きている行だけを見る
CREATE INDEX idx_profile_observations_user_live
    ON public.profile_observations (user_id, created_at)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_profile_observations_thread ON public.profile_observations (thread_id);

ALTER TABLE public.profile_observations ENABLE ROW LEVEL SECURITY;
-- 本人の画面には出さないので、authenticated 向けのポリシーは置かない


-- ------------------------------------------------------------
-- 3. 項目(2層)
-- ------------------------------------------------------------
CREATE TABLE public.profile_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    category_id uuid,
    kind text NOT NULL,
    content text NOT NULL,
    -- ai: まとめ役が書いた / user: 本人が書いた・直した(AIは文を書き換えない)
    origin text DEFAULT 'ai'::text NOT NULL,
    -- active / pending_confirm(センシティブの確認待ち。どこにも使わない) / rejected(違う)
    -- / archived(もう当てはまらない) / orphaned(根拠の会話がすべて消えた)
    status text DEFAULT 'active'::text NOT NULL,
    sensitive text DEFAULT 'none'::text NOT NULL,
    first_seen_at date,
    last_seen_at date,
    occurred_at date,
    -- 本人が見た時刻。NULLの間は「新しい」印を出す
    seen_by_user_at timestamp with time zone,
    rejected_at date,
    rejected_reason text,
    embedding extensions.vector(768),
    embedding_model text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_kind_check CHECK (kind IN ('trait', 'record'));
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_origin_check CHECK (origin IN ('ai', 'user'));
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_status_check
    CHECK (status IN ('active', 'pending_confirm', 'rejected', 'archived', 'orphaned'));
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_sensitive_check
    CHECK (sensitive IN ('none', 'religion', 'health', 'sexuality', 'politics', 'ethnicity'));
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_items
    ADD CONSTRAINT profile_items_category_id_fkey
    FOREIGN KEY (category_id) REFERENCES public.profile_categories(id) ON DELETE SET NULL;

CREATE INDEX idx_profile_items_user_status ON public.profile_items (user_id, status);

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.profile_items
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profile_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own profile items"
    ON public.profile_items FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- 項目 ↔ 観察(根拠)。観察が消えると行も消え、根拠が0件になったAI由来の項目は
-- バックエンドが orphaned にする
CREATE TABLE public.profile_item_evidence (
    item_id uuid NOT NULL,
    observation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.profile_item_evidence
    ADD CONSTRAINT profile_item_evidence_pkey PRIMARY KEY (item_id, observation_id);
ALTER TABLE ONLY public.profile_item_evidence
    ADD CONSTRAINT profile_item_evidence_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES public.profile_items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_item_evidence
    ADD CONSTRAINT profile_item_evidence_observation_id_fkey
    FOREIGN KEY (observation_id) REFERENCES public.profile_observations(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_item_evidence
    ADD CONSTRAINT profile_item_evidence_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_profile_item_evidence_observation ON public.profile_item_evidence (observation_id);

ALTER TABLE public.profile_item_evidence ENABLE ROW LEVEL SECURITY;


-- 傾向の書き直しの履歴(「変化のログ」)。書き直す前の文を残す
CREATE TABLE public.profile_item_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    user_id uuid NOT NULL,
    content text NOT NULL,
    origin text NOT NULL,
    replaced_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.profile_item_versions
    ADD CONSTRAINT profile_item_versions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_item_versions
    ADD CONSTRAINT profile_item_versions_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES public.profile_items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profile_item_versions
    ADD CONSTRAINT profile_item_versions_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_profile_item_versions_item ON public.profile_item_versions (item_id, replaced_at);

ALTER TABLE public.profile_item_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own profile item versions"
    ON public.profile_item_versions FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 4. 覚え書き(AIチャット設定)。プロフィールとは別に保存する
-- ------------------------------------------------------------
CREATE TABLE public.ai_memos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    content text NOT NULL,
    -- situation(今の状況)は必ず期限をつける
    expires_at date,
    evidence_observation_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.ai_memos
    ADD CONSTRAINT ai_memos_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.ai_memos
    ADD CONSTRAINT ai_memos_kind_check CHECK (kind IN ('answer_style', 'situation'));
ALTER TABLE ONLY public.ai_memos
    ADD CONSTRAINT ai_memos_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_ai_memos_user ON public.ai_memos (user_id);

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.ai_memos
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.ai_memos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own ai memos"
    ON public.ai_memos FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 5. 確かめたい仮説。回答役が、同じ種類の話題が出たときに自然に掘る。本人には見せない
-- ------------------------------------------------------------
CREATE TABLE public.profile_hypotheses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    content text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    evidence_observation_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    asked_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.profile_hypotheses
    ADD CONSTRAINT profile_hypotheses_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_hypotheses
    ADD CONSTRAINT profile_hypotheses_status_check CHECK (status IN ('open', 'confirmed', 'refuted', 'expired'));
ALTER TABLE ONLY public.profile_hypotheses
    ADD CONSTRAINT profile_hypotheses_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_profile_hypotheses_user_open ON public.profile_hypotheses (user_id) WHERE status = 'open';

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.profile_hypotheses
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profile_hypotheses ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 6. 「残したくない」と言われた分野。中身は持たない(中身を残すとその情報を持ち続けることになるため)
-- ------------------------------------------------------------
CREATE TABLE public.profile_blocked_areas (
    user_id uuid NOT NULL,
    area text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.profile_blocked_areas
    ADD CONSTRAINT profile_blocked_areas_pkey PRIMARY KEY (user_id, area);
ALTER TABLE ONLY public.profile_blocked_areas
    ADD CONSTRAINT profile_blocked_areas_area_check
    CHECK (area IN ('religion', 'health', 'sexuality', 'politics', 'ethnicity'));
ALTER TABLE ONLY public.profile_blocked_areas
    ADD CONSTRAINT profile_blocked_areas_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.profile_blocked_areas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own profile blocked areas"
    ON public.profile_blocked_areas FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 7. 表紙(1層): 欄ごとの書き手と、本人が書いた欄への書き直し案
-- ------------------------------------------------------------
ALTER TABLE public.user_profiles
    ADD COLUMN bio_written_by text,
    ADD COLUMN interests_written_by text,
    ADD COLUMN future_goals_written_by text;

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_bio_written_by_check CHECK (bio_written_by IN ('ai', 'user'));
ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_interests_written_by_check CHECK (interests_written_by IN ('ai', 'user'));
ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_future_goals_written_by_check CHECK (future_goals_written_by IN ('ai', 'user'));

-- これまでの表紙はすべて本人が書いたもの
UPDATE public.user_profiles SET bio_written_by = 'user' WHERE coalesce(btrim(bio), '') <> '';
UPDATE public.user_profiles SET interests_written_by = 'user' WHERE coalesce(btrim(interests), '') <> '';
UPDATE public.user_profiles SET future_goals_written_by = 'user' WHERE coalesce(btrim(future_goals), '') <> '';

-- 本人(webapp / Flutterのoutbox。どちらも本人のJWTで直接書き込む)が欄を変えたら、
-- その欄の書き手を 'user' にする。アプリ側を直さなくても漏れなく付くよう、トリガで行う。
-- バックエンド(service_role)が書くときは、書き手を明示的に 'ai' にして書く。
CREATE FUNCTION public.fn_user_profiles_mark_written_by()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = ''
    AS $$
BEGIN
    IF coalesce(auth.role(), '') <> 'authenticated' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF coalesce(btrim(NEW.bio), '') <> '' THEN NEW.bio_written_by := 'user'; END IF;
        IF coalesce(btrim(NEW.interests), '') <> '' THEN NEW.interests_written_by := 'user'; END IF;
        IF coalesce(btrim(NEW.future_goals), '') <> '' THEN NEW.future_goals_written_by := 'user'; END IF;
        RETURN NEW;
    END IF;
    IF NEW.bio IS DISTINCT FROM OLD.bio THEN
        NEW.bio_written_by := CASE WHEN coalesce(btrim(NEW.bio), '') = '' THEN NULL ELSE 'user' END;
    END IF;
    IF NEW.interests IS DISTINCT FROM OLD.interests THEN
        NEW.interests_written_by := CASE WHEN coalesce(btrim(NEW.interests), '') = '' THEN NULL ELSE 'user' END;
    END IF;
    IF NEW.future_goals IS DISTINCT FROM OLD.future_goals THEN
        NEW.future_goals_written_by := CASE WHEN coalesce(btrim(NEW.future_goals), '') = '' THEN NULL ELSE 'user' END;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_profiles_mark_written_by
    BEFORE INSERT OR UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.fn_user_profiles_mark_written_by();


CREATE TABLE public.profile_cover_proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    field text NOT NULL,
    proposed_text text NOT NULL,
    based_on_item_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone
);

ALTER TABLE ONLY public.profile_cover_proposals
    ADD CONSTRAINT profile_cover_proposals_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profile_cover_proposals
    ADD CONSTRAINT profile_cover_proposals_field_check CHECK (field IN ('bio', 'interests', 'future_goals'));
ALTER TABLE ONLY public.profile_cover_proposals
    ADD CONSTRAINT profile_cover_proposals_status_check CHECK (status IN ('pending', 'accepted', 'rejected', 'superseded'));
ALTER TABLE ONLY public.profile_cover_proposals
    ADD CONSTRAINT profile_cover_proposals_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 1つの欄に出ている案は常に1つだけ(新しい案を出すときは古い案を superseded にする)
CREATE UNIQUE INDEX uq_profile_cover_proposals_pending
    ON public.profile_cover_proposals (user_id, field)
    WHERE status = 'pending';

ALTER TABLE public.profile_cover_proposals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select own profile cover proposals"
    ON public.profile_cover_proposals FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 8. 処理の状態
-- ------------------------------------------------------------
-- スレッドごとの「どこまで観察したか」(この時刻以前の本人の発言は読み終えた)
ALTER TABLE public.chat_threads
    ADD COLUMN profile_observed_until timestamp with time zone;

-- patrol が「放置されていて、まだ読んでいない発言がある」スレッドを探すため
CREATE INDEX idx_chat_threads_profile_pending
    ON public.chat_threads (last_message_at)
    WHERE deleted_at IS NULL;

CREATE TABLE public.profile_extraction_state (
    user_id uuid NOT NULL,
    last_consolidated_at timestamp with time zone,
    -- 表紙を書き直してから、2層の項目が作られた・書き直された数
    items_changed_since_cover integer DEFAULT 0 NOT NULL,
    last_cover_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.profile_extraction_state
    ADD CONSTRAINT profile_extraction_state_pkey PRIMARY KEY (user_id);
ALTER TABLE ONLY public.profile_extraction_state
    ADD CONSTRAINT profile_extraction_state_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.profile_extraction_state
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profile_extraction_state ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 9. 近い観察・近い項目の検索(まとめ役に渡す材料を選ぶ)
--
-- チャットの search_knowledge_chunks は「user_id 引数を持たず、本人のJWTの auth.uid() で絞る」
-- 方針だが、こちらは Cloud Tasks の裏で動くバックエンドから呼ぶので本人のJWTが無い。
-- そのため user_id を引数に取る代わりに、service_role 以外からは呼べないようにする
-- (anon / authenticated の EXECUTE を剥がす)。service_role はもともと全行を読めるので、
-- この関数で読める範囲は広がらない。
-- ------------------------------------------------------------
CREATE FUNCTION public.match_profile_observations(
    p_user_id uuid,
    query_embedding extensions.vector(768),
    match_count integer DEFAULT 5,
    exclude_ids uuid[] DEFAULT '{}'::uuid[]
)
    RETURNS TABLE (id uuid, similarity double precision)
    LANGUAGE sql
    STABLE
    SET search_path = ''
    AS $$
    SELECT o.id, 1 - (o.embedding OPERATOR(extensions.<=>) query_embedding) AS similarity
    FROM public.profile_observations o
    WHERE o.user_id = p_user_id
      AND o.deleted_at IS NULL
      AND o.status <> 'discounted'
      AND o.embedding IS NOT NULL
      AND NOT (o.id = ANY(exclude_ids))
    ORDER BY o.embedding OPERATOR(extensions.<=>) query_embedding
    LIMIT match_count;
$$;

CREATE FUNCTION public.match_profile_items(
    p_user_id uuid,
    query_embedding extensions.vector(768),
    match_count integer DEFAULT 10,
    p_kind text DEFAULT NULL
)
    RETURNS TABLE (id uuid, similarity double precision)
    LANGUAGE sql
    STABLE
    SET search_path = ''
    AS $$
    SELECT i.id, 1 - (i.embedding OPERATOR(extensions.<=>) query_embedding) AS similarity
    FROM public.profile_items i
    WHERE i.user_id = p_user_id
      AND i.status IN ('active', 'pending_confirm')
      AND i.embedding IS NOT NULL
      AND (p_kind IS NULL OR i.kind = p_kind)
    ORDER BY i.embedding OPERATOR(extensions.<=>) query_embedding
    LIMIT match_count;
$$;

REVOKE ALL ON FUNCTION public.match_profile_observations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.match_profile_items FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_profile_observations TO service_role;
GRANT EXECUTE ON FUNCTION public.match_profile_items TO service_role;


-- ------------------------------------------------------------
-- 10. patrol 用: 観察役・まとめ役に回す対象を探す(service_role 専用)
-- ------------------------------------------------------------
-- 最後の発言から idle_minutes 以上たっていて、まだ観察していない発言があるスレッド。
-- max_age_days より前に止まったスレッドは対象にしない(導入時に古い会話を一気に読まないため)
CREATE FUNCTION public.list_threads_pending_profile_observation(
    idle_minutes integer DEFAULT 30,
    max_age_days integer DEFAULT 14,
    max_count integer DEFAULT 50
)
    RETURNS TABLE (thread_id uuid, user_id uuid, last_message_at timestamp with time zone)
    LANGUAGE sql
    STABLE
    SET search_path = ''
    AS $$
    SELECT t.id, t.user_id, t.last_message_at
    FROM public.chat_threads t
    WHERE t.deleted_at IS NULL
      AND t.last_message_at < now() - make_interval(mins => idle_minutes)
      AND t.last_message_at > now() - make_interval(days => max_age_days)
      AND (t.profile_observed_until IS NULL OR t.profile_observed_until < t.last_message_at)
    ORDER BY t.last_message_at
    LIMIT max_count;
$$;

-- まとめ役に渡していない観察が min_new 件以上あるか、いちばん古いものが max_wait_days 以上たったユーザー
CREATE FUNCTION public.list_users_pending_profile_consolidation(
    min_new integer DEFAULT 5,
    max_wait_days integer DEFAULT 7,
    max_count integer DEFAULT 50
)
    RETURNS TABLE (user_id uuid, pending_count bigint, oldest_at timestamp with time zone)
    LANGUAGE sql
    STABLE
    SET search_path = ''
    AS $$
    SELECT o.user_id, count(*) AS pending_count, min(o.created_at) AS oldest_at
    FROM public.profile_observations o
    WHERE o.deleted_at IS NULL
      AND o.consolidated_at IS NULL
      AND o.status <> 'discounted'
    GROUP BY o.user_id
    HAVING count(*) >= min_new OR min(o.created_at) < now() - make_interval(days => max_wait_days)
    ORDER BY min(o.created_at)
    LIMIT max_count;
$$;

REVOKE ALL ON FUNCTION public.list_threads_pending_profile_observation FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_users_pending_profile_consolidation FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_threads_pending_profile_observation TO service_role;
GRANT EXECUTE ON FUNCTION public.list_users_pending_profile_consolidation TO service_role;
