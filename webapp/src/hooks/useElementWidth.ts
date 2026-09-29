import { useCallback, useRef, useState } from 'react';

/**
 * 要素自身の実表示幅(border-box、ResizeObserverで計測)を返すフック。ウィンドウ幅
 * ベースの@media/useMediaQueryと違い、チャットパネルのドック(.app-shell の
 * padding-right)のように「ウィンドウ幅は変わらないが実際に使える幅だけが
 * 変わる」ケースにも追従できる。
 *
 * CSSのコンテナクエリ(@container)で同じことは出来るが、container-typeは
 * position:fixed子孫のcontaining blockを巻き込んでしまう
 * (モーダル/シートがビューポート基準でなくこの要素基準になり、背景スクロール時に
 * ズレる恐れがある)ため、副作用のないJS計測で代替している。
 *
 * ローディング後に初めて描画される要素にも付けられるよう、useRefではなく
 * callback refを返す(要素がマウントされた時点で計測を始める)。
 */
export function useElementWidth<T extends HTMLElement>(): [(node: T | null) => void, number] {
  const [width, setWidth] = useState(0);
  const observerRef = useRef<ResizeObserver | null>(null);

  const ref = useCallback((node: T | null) => {
    observerRef.current?.disconnect();
    observerRef.current = null;
    if (!node) return;

    setWidth(node.getBoundingClientRect().width);

    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      setWidth(entry.borderBoxSize?.[0]?.inlineSize ?? entry.target.getBoundingClientRect().width);
    });
    observer.observe(node);
    observerRef.current = observer;
  }, []);

  return [ref, width];
}
