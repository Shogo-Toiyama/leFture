import { useCallback, useEffect, useState } from 'react';
import { deleteChatThread, listChatThreads, renameChatThread } from '../lib/chat';
import type { ChatThread } from '../types/chat';

/** 会話(スレッド)一覧。新しく話した順。 */
export function useChatThreads() {
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);

  const refetch = useCallback(() => {
    setLoading(true);
    setError(null);
    listChatThreads()
      .then(setThreads)
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    refetch();
  }, [refetch]);

  const rename = useCallback(async (threadId: string, title: string) => {
    await renameChatThread(threadId, title);
    setThreads((prev) => prev.map((t) => (t.id === threadId ? { ...t, title } : t)));
  }, []);

  const remove = useCallback(async (threadId: string) => {
    await deleteChatThread(threadId);
    setThreads((prev) => prev.filter((t) => t.id !== threadId));
  }, []);

  return { threads, loading, error, refetch, rename, remove };
}
