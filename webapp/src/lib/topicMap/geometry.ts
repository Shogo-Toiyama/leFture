/**
 * user_interface/lib/presentation/widgets/topic_map/force_layout/convex_hull.dart のTS移植。
 * 凸包(Andrewのmonotone chain)・多角形の外側への膨張・滑らかな「ブロブ」パスの生成。
 */

export interface Point {
  x: number;
  y: number;
}

export function convexHull(points: Point[]): Point[] {
  const seen = new Set<string>();
  const unique: Point[] = [];
  for (const p of points) {
    const key = `${p.x},${p.y}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(p);
  }
  if (unique.length < 3) return unique;

  unique.sort((a, b) => (a.x !== b.x ? a.x - b.x : a.y - b.y));

  const cross = (o: Point, a: Point, b: Point) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  const lower: Point[] = [];
  for (const p of unique) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.pop();
    }
    lower.push(p);
  }

  const upper: Point[] = [];
  for (let i = unique.length - 1; i >= 0; i--) {
    const p = unique[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.pop();
    }
    upper.push(p);
  }

  lower.pop();
  upper.pop();
  return [...lower, ...upper];
}

export function inflatePolygon(hull: Point[], padding: number): Point[] {
  if (hull.length === 0) return hull;
  let cx = 0;
  let cy = 0;
  for (const p of hull) {
    cx += p.x;
    cy += p.y;
  }
  cx /= hull.length;
  cy /= hull.length;
  return hull.map((p) => {
    const dx = p.x - cx;
    const dy = p.y - cy;
    const len = Math.hypot(dx, dy);
    if (len < 0.001) return { x: p.x + padding, y: p.y };
    return { x: p.x + (dx / len) * padding, y: p.y + (dy / len) * padding };
  });
}

/** 多角形の各辺の中点を通る二次ベジェで丸め、facetedな多角形を柔らかいブロブに見せる。 */
function smoothClosedPathD(pts: Point[]): string {
  const n = pts.length;
  const mid = (a: Point, b: Point) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

  const firstMid = mid(pts[n - 1], pts[0]);
  let d = `M ${firstMid.x} ${firstMid.y} `;
  for (let i = 0; i < n; i++) {
    const current = pts[i];
    const next = pts[(i + 1) % n];
    const m = mid(current, next);
    d += `Q ${current.x} ${current.y} ${m.x} ${m.y} `;
  }
  d += 'Z';
  return d;
}

export type ClusterBlobShape =
  | { kind: 'circle'; center: Point; radius: number }
  | { kind: 'capsule'; start: Point; end: Point; radius: number }
  | { kind: 'path'; d: string; points: Point[] };

export function buildClusterBlob(points: Point[], padding: number): ClusterBlobShape {
  if (points.length === 0) return { kind: 'circle', center: { x: 0, y: 0 }, radius: 0 };
  if (points.length === 1) return { kind: 'circle', center: points[0], radius: padding };

  const hull = convexHull(points);
  if (hull.length < 3) {
    let a = points[0];
    let b = points[0];
    let maxDist = 0;
    for (const p of points) {
      for (const q of points) {
        const d = Math.hypot(p.x - q.x, p.y - q.y);
        if (d > maxDist) {
          maxDist = d;
          a = p;
          b = q;
        }
      }
    }
    return { kind: 'capsule', start: a, end: b, radius: padding };
  }

  const inflated = inflatePolygon(hull, padding);
  return { kind: 'path', d: smoothClosedPathD(inflated), points: inflated };
}

/** クラスタの名前(Cluster View)を出す位置 = ブロブの中心。 */
export function clusterBlobCenter(blob: ClusterBlobShape): Point {
  if (blob.kind === 'circle') return blob.center;
  if (blob.kind === 'capsule') return { x: (blob.start.x + blob.end.x) / 2, y: (blob.start.y + blob.end.y) / 2 };
  const xs = blob.points.map((p) => p.x);
  const ys = blob.points.map((p) => p.y);
  return { x: (Math.min(...xs) + Math.max(...xs)) / 2, y: (Math.min(...ys) + Math.max(...ys)) / 2 };
}

/** クラスタの名前(Lecture/Topic View)を出す位置 = ブロブ最上部の少し外側。 */
export function clusterBlobOutsideTopAnchor(blob: ClusterBlobShape): Point {
  if (blob.kind === 'circle') return { x: blob.center.x, y: blob.center.y - blob.radius };
  if (blob.kind === 'capsule') {
    const top = blob.start.y < blob.end.y ? blob.start : blob.end;
    const midX = (blob.start.x + blob.end.x) / 2;
    return { x: midX, y: top.y - blob.radius };
  }
  const xs = blob.points.map((p) => p.x);
  const ys = blob.points.map((p) => p.y);
  return { x: (Math.min(...xs) + Math.max(...xs)) / 2, y: Math.min(...ys) };
}

/** Path2D + Canvas2Dの isPointInPath を使って、DOM非依存でヒットテストする。 */
let hitTestCtx: CanvasRenderingContext2D | null = null;
function getHitTestContext(): CanvasRenderingContext2D | null {
  if (typeof document === 'undefined') return null;
  if (!hitTestCtx) {
    const canvas = document.createElement('canvas');
    hitTestCtx = canvas.getContext('2d');
  }
  return hitTestCtx;
}

export function clusterBlobContains(blob: ClusterBlobShape, point: Point): boolean {
  if (blob.kind === 'circle') {
    return Math.hypot(point.x - blob.center.x, point.y - blob.center.y) <= blob.radius;
  }
  if (blob.kind === 'capsule') {
    const ab = { x: blob.end.x - blob.start.x, y: blob.end.y - blob.start.y };
    const abLenSq = ab.x * ab.x + ab.y * ab.y;
    const t = abLenSq === 0 ? 0 : Math.min(1, Math.max(0, ((point.x - blob.start.x) * ab.x + (point.y - blob.start.y) * ab.y) / abLenSq));
    const projX = blob.start.x + ab.x * t;
    const projY = blob.start.y + ab.y * t;
    return Math.hypot(point.x - projX, point.y - projY) <= blob.radius;
  }
  const ctx = getHitTestContext();
  if (!ctx) return false;
  const path = new Path2D(blob.d);
  return ctx.isPointInPath(path, point.x, point.y);
}
