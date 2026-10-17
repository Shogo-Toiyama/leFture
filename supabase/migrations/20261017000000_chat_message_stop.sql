-- ============================================================
-- 横断チャットボット: 返答の途中停止(docs/chatbot_context_and_retrieval_roadmap.md 2-12, 2026-10-17に合意)
--
-- - chat_messages.status に 'stopped' を足す。止めたところまでの本文(空のこともある)を返答として残し、
--   履歴・要約に使う。課金は発生した原価の分だけ(締め処理で請求)。
-- - stop_requested_at: 停止ボタンが押された時刻(返答の行に書く)。生成を走らせているインスタンスが
--   課金のある呼び出しの直前と、1秒ごとの見回りでこれを読み、以降の呼び出しをしない。
--   Cloud Runが複数インスタンスでも、停止のリクエストがどのインスタンスに届いても効くよう、信号はDBに置く。
-- - 検索インデックス(chat_turn)のトリガは、これまで通り 'complete' だけを積む(途中の返答は検索に出さない)。
-- ============================================================

ALTER TABLE public.chat_messages
    DROP CONSTRAINT chat_messages_status_check;

-- streaming: 生成中 / complete: 完了 / error: 失敗(課金なし)
-- blocked: 不適切な内容として断った(課金なし、以降の会話履歴に入れない)
-- crisis: 危機対応の定型文を返した(課金なし)
-- stopped: 生徒が途中で止めた(止めたところまでの本文。発生した原価の分だけ課金)
ALTER TABLE public.chat_messages
    ADD CONSTRAINT chat_messages_status_check
    CHECK (status IN ('streaming', 'complete', 'error', 'blocked', 'crisis', 'stopped'));

ALTER TABLE public.chat_messages
    ADD COLUMN stop_requested_at timestamp with time zone;
