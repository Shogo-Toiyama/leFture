/**
 * topic_map_style.dart / zoom_detail.dart のTS移植。Webはダークテーマのみなので
 * clusterDarkパレットだけを使う。
 */

export const CLUSTER_PALETTE: string[] = [
  '#3987E5',
  '#199E70',
  '#C98500',
  '#008300',
  '#B45CD9',
  '#E66767',
  '#D93E88',
  '#D95926',
  '#B25AA7',
  '#C95461',
  '#9E62C0',
  '#499537',
];

export function clusterColor(index: number): string {
  return CLUSTER_PALETTE[((index % CLUSTER_PALETTE.length) + CLUSTER_PALETTE.length) % CLUSTER_PALETTE.length];
}

export const NODE_RADIUS = 18;
export const GHOST_NODE_RADIUS = 14;
export const CLUSTER_BLOB_PADDING = 46;

/** ズームインするほど詳細(ノード半径・エッジ幅・文字)が画面上で一定サイズに収束する
 * "Google Maps的デクラッター"。 */
const DETAIL_SHRINK_START_SCALE = 1.55;

export function detailShrinkFactor(currentScale: number): number {
  if (currentScale <= DETAIL_SHRINK_START_SCALE) return 1.0;
  return DETAIL_SHRINK_START_SCALE / currentScale;
}

export const RELATION_LABEL_MIN_SCALE = DETAIL_SHRINK_START_SCALE;

const CLUSTER_LABEL_GROW_START_SCALE = 1.0;
const CLUSTER_LABEL_MAX_GROW = 2.0;

/** ズームアウトするほどクラスタ中心ラベルが画面上で一定サイズを保つように拡大する。 */
export function clusterLabelGrowFactor(currentScale: number): number {
  if (currentScale >= CLUSTER_LABEL_GROW_START_SCALE) return 1.0;
  return Math.min(CLUSTER_LABEL_MAX_GROW, Math.max(1.0, CLUSTER_LABEL_GROW_START_SCALE / currentScale));
}

export const CLUSTER_CENTER_LABEL_MAX_SCALE = 1.15;
