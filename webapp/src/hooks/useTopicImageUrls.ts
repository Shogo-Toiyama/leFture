import { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';

/**
 * 複数のトピック画像をまとめてobject URLに解決する。カードをめくるたびに
 * 取り直すとちらつくため、ビューア表示中は一度だけ取得して保持する。
 * 返り値は storagePath -> object URL のマップ。
 */
export function useTopicImageUrls(paths: (string | null | undefined)[]): Record<string, string> {
  const key = paths.filter(Boolean).join('|');
  const [urls, setUrls] = useState<Record<string, string>>({});

  useEffect(() => {
    const wanted = key ? key.split('|') : [];
    if (wanted.length === 0) {
      setUrls({});
      return;
    }

    let cancelled = false;
    const created: string[] = [];

    Promise.all(
      wanted.map(async (path) => {
        try {
          const url = await fetchArtifactObjectUrl(path);
          created.push(url);
          return [path, url] as const;
        } catch {
          return null;
        }
      })
    ).then((pairs) => {
      if (cancelled) return;
      const next: Record<string, string> = {};
      for (const pair of pairs) {
        if (pair) next[pair[0]] = pair[1];
      }
      setUrls(next);
    });

    return () => {
      cancelled = true;
      created.forEach((url) => URL.revokeObjectURL(url));
    };
  }, [key]);

  return urls;
}
