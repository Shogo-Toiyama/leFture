import { useEffect, useState } from 'react';

/**
 * CSSのブレークポイントをJS側からも見るためのフック。
 * 横並びのパネルとボトムシートでは振る舞いを変える必要があるため、
 * レイアウトの分岐条件をCSSと一箇所で揃えて共有する。
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() =>
    typeof window === 'undefined' ? false : window.matchMedia(query).matches
  );

  useEffect(() => {
    const list = window.matchMedia(query);
    const onChange = (event: MediaQueryListEvent) => setMatches(event.matches);
    setMatches(list.matches);
    list.addEventListener('change', onChange);
    return () => list.removeEventListener('change', onChange);
  }, [query]);

  return matches;
}

/** パネルを横に並べず、ボトムシートとして重ねる幅かどうか。 */
export const STACKED_PANELS_QUERY = '(max-width: 900px)';
