import { useEffect, useState } from 'react';
import { getChatAttachmentFileUrl } from '../lib/chat';

/**
 * 添付した画像の資料を表示するURL(チップの小さな見本・一覧に使う)。署名付きURLは10分で切れるので、
 * 9分だけメモリに置いて使い回す。同じ画像を同時に頼んだら、1回の問い合わせを共有する。
 */
const CACHE_MS = 9 * 60 * 1000;
const cache = new Map<string, { url: string; expires: number }>();
const inflight = new Map<string, Promise<string>>();

function fetchUrl(attachmentId: string): Promise<string> {
  const hit = cache.get(attachmentId);
  if (hit && hit.expires > Date.now()) return Promise.resolve(hit.url);
  let p = inflight.get(attachmentId);
  if (!p) {
    p = getChatAttachmentFileUrl(attachmentId)
      .then((r) => {
        cache.set(attachmentId, { url: r.url, expires: Date.now() + CACHE_MS });
        return r.url;
      })
      .finally(() => inflight.delete(attachmentId));
    inflight.set(attachmentId, p);
  }
  return p;
}

/** attachmentIdがnullなら何もしない(画像でない・まだ送っていない)。 */
export function useAttachmentImageUrl(attachmentId: string | null | undefined): string | null {
  const [url, setUrl] = useState<string | null>(() => {
    const hit = attachmentId ? cache.get(attachmentId) : undefined;
    return hit && hit.expires > Date.now() ? hit.url : null;
  });
  useEffect(() => {
    if (!attachmentId) {
      setUrl(null);
      return;
    }
    let cancelled = false;
    fetchUrl(attachmentId)
      .then((u) => !cancelled && setUrl(u))
      .catch(() => !cancelled && setUrl(null));
    return () => {
      cancelled = true;
    };
  }, [attachmentId]);
  return url;
}
