-- 20261025160000_add_deep_note_figures.sql
-- DeepNotes 内の図解（Diagram / Chart）の HTML/SVG 自己完結コードを保存するテーブル

CREATE TABLE IF NOT EXISTS public.deep_note_figures (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    lecture_id uuid NOT NULL REFERENCES public.lectures(id) ON DELETE CASCADE,
    topic_number smallint NOT NULL,
    figure_index smallint NOT NULL,         -- そのトピック内で何番目の図か (0, 1)
    figure_type text NOT NULL,              -- 'diagram' | 'chart'
    title text NOT NULL,
    description text,
    html_content text NOT NULL,             -- 生成された完全自己完結HTML/CSS/SVG
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    user_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- 冪等性保証: 同じ講義・トピック・インデックスの重複を防ぐ
    CONSTRAINT unique_lecture_topic_figure UNIQUE (lecture_id, topic_number, figure_index)
);

-- RLS（Row Level Security）ポリシー設定
ALTER TABLE public.deep_note_figures ENABLE ROW LEVEL SECURITY;

CREATE POLICY deep_note_figures_select_own ON public.deep_note_figures
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY deep_note_figures_insert_own ON public.deep_note_figures
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY deep_note_figures_update_own ON public.deep_note_figures
    FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY deep_note_figures_delete_own ON public.deep_note_figures
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_deep_note_figures_lecture_topic 
    ON public.deep_note_figures (lecture_id, topic_number);
