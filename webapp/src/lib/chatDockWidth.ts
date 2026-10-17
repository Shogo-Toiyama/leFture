/**
 * 右側のチャットパネル(ドック)の幅。ドラッグで変えられ、端末ごとに覚える(localStorage)。
 *
 * 保存するのは「好みの幅」で、実際に使う幅は画面の幅に収まるよう毎回丸める。
 * 小さい画面で開いてから広い画面に戻したときに、好みの幅がそのまま戻るように。
 */

/** 初期値(ダブルクリックで戻す幅)。 */
export const CHAT_DOCK_DEFAULT_PX = 460;
/** チャット側の最小幅。初期値と同じなので、広げることはできるが、これより細くはならない。 */
export const CHAT_DOCK_MIN_PX = 460;
/** メインページ側の最小幅。チャットを広げすぎて、読んでいるページが潰れないようにする。 */
export const CHAT_MAIN_MIN_PX = 460;

const STORAGE_KEY = 'chat_dock_width';

/**
 * 画面の幅に対して、チャットが取れる最大幅。メイン側の最小幅を残す。
 * 画面が小さくてチャット側の最小幅すら収まらない帯(901〜919px)では、チャットの最小幅を優先する
 * (900px以下はボトムシートになるので、ここに来るのは901px以上)。
 */
export function maxDockWidth(viewportPx: number): number {
  return Math.max(CHAT_DOCK_MIN_PX, viewportPx - CHAT_MAIN_MIN_PX);
}

export function clampDockWidth(px: number, viewportPx: number): number {
  return Math.round(Math.min(Math.max(px, CHAT_DOCK_MIN_PX), maxDockWidth(viewportPx)));
}

/** 保存してある好みの幅。無い・壊れているときは初期値。 */
export function loadDockWidth(): number {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const value = raw === null ? NaN : Number(raw);
    return Number.isFinite(value) && value >= CHAT_DOCK_MIN_PX ? value : CHAT_DOCK_DEFAULT_PX;
  } catch {
    return CHAT_DOCK_DEFAULT_PX;
  }
}

/** nullなら保存を消す(初期値に戻したとき)。保存できない環境(プライベートウィンドウ等)では黙って諦める。 */
export function saveDockWidth(px: number | null): void {
  try {
    if (px === null || px === CHAT_DOCK_DEFAULT_PX) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, String(px));
  } catch {
    /* 保存できなくても、このセッションの間は変えられる */
  }
}
