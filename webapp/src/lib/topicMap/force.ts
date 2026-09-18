/**
 * user_interface/lib/presentation/widgets/topic_map/force_layout/graph_force_simulation.dart
 * の忠実なTS移植。ノード同士の反発・エッジのバネ・同クラスタの弱い引力・次数2ノードの
 * 直線化・エッジ-ノード反発・中心引力を毎ステップ適用し、クラスタ同士は最後に
 * 円の重なりを解消する形で強制的に分離する(スプリングではなく位置補正)。
 * seed固定(=42)なので、同じ入力なら常に同じレイアウトに収束する。
 */

export interface ForceNode {
  id: string;
  clusterId: string | null;
  x: number;
  y: number;
  vx: number;
  vy: number;
}

interface EdgePair {
  source: string;
  target: string;
}

const REPULSION_K = 52000;
const EDGE_SPRING_K = 0.05;
const EDGE_IDEAL_LENGTH = 185;
const CLUSTER_SPRING_K = 0.14;
const CLUSTER_IDEAL_LENGTH = 140;
const CENTERING_K = 0.008;
const VELOCITY_DAMPING = 0.8;
const MIN_DISTANCE = 1.0;
const MAX_FORCE_PER_STEP = 70;

const STRAIGHTEN_K = 0.06;
const EDGE_REPULSION_K = 9000;
const EDGE_CLEARANCE = 42;

/** cluster_geometry.dart の kClusterBlobPadding と揃えてある(シミュレーションと描画の食い違い防止)。 */
const CLUSTER_BOUNDING_PADDING = 46;
const CLUSTER_SEPARATION_GAP = 24;

const ALPHA_DECAY = 0.965;
const ALPHA_MIN = 0.001;

/** 決定論的な疑似乱数(mulberry32)。Flutter版のdart:math Random(seed)と同一列にはならないが、
 * 「同じ入力なら毎回同じレイアウト」という性質だけは揃う。 */
function makeRng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class GraphForceSimulation {
  nodes = new Map<string, ForceNode>();
  alpha = 1.0;

  private edgePairs: EdgePair[] = [];
  private clusterPairs: EdgePair[] = [];
  private straightenTriples: [string, string, string][] = [];
  private bounds: { width: number; height: number };
  private jitterRandom = makeRng(7);

  constructor(opts: {
    nodeIds: string[];
    clusterIdByNodeId: Map<string, string | null>;
    edgePairs: EdgePair[];
    clusterOrder: string[];
    bounds: { width: number; height: number };
    seed?: number;
  }) {
    this.bounds = opts.bounds;
    const rand = makeRng(opts.seed ?? 42);
    this.seedInitialPositions(opts.nodeIds, opts.clusterIdByNodeId, opts.edgePairs, opts.clusterOrder, opts.bounds, rand);

    this.edgePairs = opts.edgePairs.filter((e) => this.nodes.has(e.source) && this.nodes.has(e.target));

    const byCluster = new Map<string, string[]>();
    for (const id of opts.nodeIds) {
      const clusterId = opts.clusterIdByNodeId.get(id);
      if (!clusterId) continue;
      if (!byCluster.has(clusterId)) byCluster.set(clusterId, []);
      byCluster.get(clusterId)!.push(id);
    }
    for (const ids of byCluster.values()) {
      for (let i = 0; i < ids.length; i++) {
        for (let j = i + 1; j < ids.length; j++) {
          this.clusterPairs.push({ source: ids[i], target: ids[j] });
        }
      }
    }

    const neighbors = new Map<string, string[]>();
    for (const e of this.edgePairs) {
      if (!neighbors.has(e.source)) neighbors.set(e.source, []);
      if (!neighbors.has(e.target)) neighbors.set(e.target, []);
      neighbors.get(e.source)!.push(e.target);
      neighbors.get(e.target)!.push(e.source);
    }
    for (const [id, list] of neighbors.entries()) {
      if (list.length === 2) this.straightenTriples.push([id, list[0], list[1]]);
    }
  }

  private seedInitialPositions(
    nodeIds: string[],
    clusterIdByNodeId: Map<string, string | null>,
    edgePairs: EdgePair[],
    clusterOrder: string[],
    bounds: { width: number; height: number },
    rand: () => number
  ) {
    const byCluster = new Map<string, string[]>();
    const unclustered: string[] = [];
    for (const id of nodeIds) {
      const clusterId = clusterIdByNodeId.get(id) ?? null;
      if (!clusterId) {
        unclustered.push(id);
      } else {
        if (!byCluster.has(clusterId)) byCluster.set(clusterId, []);
        byCluster.get(clusterId)!.push(id);
      }
    }

    const intraNeighbors = new Map<string, string[]>();
    const intraInDegree = new Map<string, number>();
    const crossClusterParentIds = new Set<string>();
    for (const e of edgePairs) {
      const clusterA = clusterIdByNodeId.get(e.source) ?? null;
      const clusterB = clusterIdByNodeId.get(e.target) ?? null;
      if (!clusterA || !clusterB) continue;
      if (clusterA !== clusterB) {
        crossClusterParentIds.add(e.source);
        continue;
      }
      if (!intraNeighbors.has(e.source)) intraNeighbors.set(e.source, []);
      if (!intraNeighbors.has(e.target)) intraNeighbors.set(e.target, []);
      intraNeighbors.get(e.source)!.push(e.target);
      intraNeighbors.get(e.target)!.push(e.source);
      intraInDegree.set(e.target, (intraInDegree.get(e.target) ?? 0) + 1);
    }

    const effectiveClusterOrder = [
      ...clusterOrder,
      ...Array.from(byCluster.keys()).filter((id) => !clusterOrder.includes(id)),
    ];

    const center = { x: bounds.width / 2, y: bounds.height / 2 };
    const homeRadius = Math.min(bounds.width, bounds.height) * 0.22;
    const clusterCount = effectiveClusterOrder.length;
    const wedgeWidth = clusterCount > 0 ? (2 * Math.PI) / clusterCount : 2 * Math.PI;
    const wedgeHalfSpread = (wedgeWidth / 2) * 0.8;

    for (let ci = 0; ci < effectiveClusterOrder.length; ci++) {
      const ids = byCluster.get(effectiveClusterOrder[ci]);
      if (!ids || ids.length === 0) continue;

      const wedgeCenterAngle = clusterCount <= 1 ? -Math.PI / 2 : (2 * Math.PI * ci) / clusterCount - Math.PI / 2;

      const roots = ids.filter((id) => (intraInDegree.get(id) ?? 0) === 0 || crossClusterParentIds.has(id));
      const effectiveRoots = roots.length === 0 ? [ids[0]] : roots;

      const layerOf = new Map<string, number>();
      const queue: string[] = [];
      for (const root of effectiveRoots) {
        layerOf.set(root, 0);
        queue.push(root);
      }
      let qi = 0;
      while (qi < queue.length) {
        const current = queue[qi++];
        const currentLayer = layerOf.get(current)!;
        for (const neighbor of intraNeighbors.get(current) ?? []) {
          if (layerOf.has(neighbor)) continue;
          layerOf.set(neighbor, currentLayer + 1);
          queue.push(neighbor);
        }
      }
      const maxLayer = layerOf.size === 0 ? 0 : Math.max(...layerOf.values());
      for (const id of ids) {
        if (!layerOf.has(id)) layerOf.set(id, maxLayer + 1);
      }

      const byLayer = new Map<number, string[]>();
      for (const id of ids) {
        const layer = layerOf.get(id)!;
        if (!byLayer.has(layer)) byLayer.set(layer, []);
        byLayer.get(layer)!.push(id);
      }

      for (const [layer, layerIds] of byLayer.entries()) {
        const n = layerIds.length;
        const radius = homeRadius + layer * 75.0;
        for (let k = 0; k < n; k++) {
          const angleOffset = n <= 1 ? 0.0 : wedgeHalfSpread * ((2 * (k + 0.5)) / n - 1);
          const angle = wedgeCenterAngle + angleOffset;
          const x = center.x + Math.cos(angle) * radius;
          const y = center.y + Math.sin(angle) * radius;
          this.nodes.set(layerIds[k], {
            id: layerIds[k],
            clusterId: effectiveClusterOrder[ci],
            x,
            y,
            vx: 0,
            vy: 0,
          });
        }
      }
    }

    for (const id of unclustered) {
      const x = bounds.width * 0.5 + (rand() - 0.5) * bounds.width * 0.7;
      const y = bounds.height * 0.5 + (rand() - 0.5) * bounds.height * 0.7;
      this.nodes.set(id, { id, clusterId: null, x, y, vx: 0, vy: 0 });
    }
  }

  get isRunning() {
    return this.alpha > ALPHA_MIN;
  }

  /** 収束するまで(またはステップ上限まで)一気に進める。初期表示は静止済みの状態で出す。 */
  runToConvergence(maxSteps = 2000) {
    let steps = 0;
    while (this.isRunning && steps < maxSteps) {
      this.step();
      steps++;
    }
  }

  step() {
    if (!this.isRunning) return;

    const ids = Array.from(this.nodes.keys());
    const forces = new Map<string, { x: number; y: number }>();
    for (const id of ids) forces.set(id, { x: 0, y: 0 });

    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const a = this.nodes.get(ids[i])!;
        const b = this.nodes.get(ids[j])!;
        let dx = a.x - b.x;
        let dy = a.y - b.y;
        let dist = Math.hypot(dx, dy);
        if (dist < MIN_DISTANCE) {
          const angle = this.jitterRandom() * 2 * Math.PI;
          dx = Math.cos(angle) * MIN_DISTANCE;
          dy = Math.sin(angle) * MIN_DISTANCE;
          dist = MIN_DISTANCE;
        }
        const forceMag = REPULSION_K / (dist * dist);
        const fx = (dx / dist) * forceMag;
        const fy = (dy / dist) * forceMag;
        forces.get(ids[i])!.x += fx;
        forces.get(ids[i])!.y += fy;
        forces.get(ids[j])!.x -= fx;
        forces.get(ids[j])!.y -= fy;
      }
    }

    const applySpring = (aId: string, bId: string, idealLength: number, springK: number) => {
      const a = this.nodes.get(aId)!;
      const b = this.nodes.get(bId)!;
      let dx = b.x - a.x;
      let dy = b.y - a.y;
      let dist = Math.hypot(dx, dy);
      if (dist < 0.001) dist = 0.001;
      const forceMag = springK * (dist - idealLength);
      const fx = (dx / dist) * forceMag;
      const fy = (dy / dist) * forceMag;
      forces.get(aId)!.x += fx;
      forces.get(aId)!.y += fy;
      forces.get(bId)!.x -= fx;
      forces.get(bId)!.y -= fy;
    };

    for (const e of this.edgePairs) applySpring(e.source, e.target, EDGE_IDEAL_LENGTH, EDGE_SPRING_K);
    for (const p of this.clusterPairs) applySpring(p.source, p.target, CLUSTER_IDEAL_LENGTH, CLUSTER_SPRING_K);

    for (const [nodeId, neighborA, neighborB] of this.straightenTriples) {
      const posA = this.nodes.get(neighborA);
      const posB = this.nodes.get(neighborB);
      const node = this.nodes.get(nodeId);
      if (!posA || !posB || !node) continue;
      const midX = (posA.x + posB.x) * 0.5;
      const midY = (posA.y + posB.y) * 0.5;
      forces.get(nodeId)!.x += (midX - node.x) * STRAIGHTEN_K;
      forces.get(nodeId)!.y += (midY - node.y) * STRAIGHTEN_K;
    }

    for (const e of this.edgePairs) {
      const start = this.nodes.get(e.source)!;
      const end = this.nodes.get(e.target)!;
      const segX = end.x - start.x;
      const segY = end.y - start.y;
      const segLenSq = segX * segX + segY * segY;
      if (segLenSq < 1.0) continue;

      for (const id of ids) {
        if (id === e.source || id === e.target) continue;
        const point = this.nodes.get(id)!;
        let t = ((point.x - start.x) * segX + (point.y - start.y) * segY) / segLenSq;
        t = Math.min(1, Math.max(0, t));
        const closestX = start.x + segX * t;
        const closestY = start.y + segY * t;
        let dx = point.x - closestX;
        let dy = point.y - closestY;
        let dist = Math.hypot(dx, dy);
        if (dist >= EDGE_CLEARANCE) continue;
        if (dist < 0.5) {
          const angle = this.jitterRandom() * 2 * Math.PI;
          dx = Math.cos(angle);
          dy = Math.sin(angle);
          dist = 1.0;
        }
        const forceMag = EDGE_REPULSION_K / (dist * dist);
        forces.get(id)!.x += (dx / dist) * forceMag;
        forces.get(id)!.y += (dy / dist) * forceMag;
      }
    }

    const centerX = this.bounds.width / 2;
    const centerY = this.bounds.height / 2;
    for (const id of ids) {
      const node = this.nodes.get(id)!;
      forces.get(id)!.x += (centerX - node.x) * CENTERING_K;
      forces.get(id)!.y += (centerY - node.y) * CENTERING_K;
    }

    for (const id of ids) {
      const node = this.nodes.get(id)!;
      let fx = forces.get(id)!.x * this.alpha;
      let fy = forces.get(id)!.y * this.alpha;
      const fLen = Math.hypot(fx, fy);
      if (fLen > MAX_FORCE_PER_STEP) {
        fx = (fx / fLen) * MAX_FORCE_PER_STEP;
        fy = (fy / fLen) * MAX_FORCE_PER_STEP;
      }
      node.vx = (node.vx + fx) * VELOCITY_DAMPING;
      node.vy = (node.vy + fy) * VELOCITY_DAMPING;
      node.x += node.vx;
      node.y += node.vy;
    }

    this.separateClusters();

    this.alpha *= ALPHA_DECAY;
  }

  private separateClusters() {
    const byCluster = new Map<string, string[]>();
    for (const node of this.nodes.values()) {
      if (!node.clusterId) continue;
      if (!byCluster.has(node.clusterId)) byCluster.set(node.clusterId, []);
      byCluster.get(node.clusterId)!.push(node.id);
    }
    if (byCluster.size < 2) return;

    const clusterIds = Array.from(byCluster.keys());
    const centroids = new Map<string, { x: number; y: number }>();
    const radii = new Map<string, number>();
    for (const clusterId of clusterIds) {
      const ids = byCluster.get(clusterId)!;
      let sumX = 0;
      let sumY = 0;
      for (const id of ids) {
        const n = this.nodes.get(id)!;
        sumX += n.x;
        sumY += n.y;
      }
      const cx = sumX / ids.length;
      const cy = sumY / ids.length;
      let maxDist = 0;
      for (const id of ids) {
        const n = this.nodes.get(id)!;
        const d = Math.hypot(n.x - cx, n.y - cy);
        if (d > maxDist) maxDist = d;
      }
      centroids.set(clusterId, { x: cx, y: cy });
      radii.set(clusterId, maxDist + CLUSTER_BOUNDING_PADDING);
    }

    for (let i = 0; i < clusterIds.length; i++) {
      for (let j = i + 1; j < clusterIds.length; j++) {
        const a = clusterIds[i];
        const b = clusterIds[j];
        const centerA = centroids.get(a)!;
        const centerB = centroids.get(b)!;
        let dx = centerB.x - centerA.x;
        let dy = centerB.y - centerA.y;
        let dist = Math.hypot(dx, dy);
        const minSeparation = radii.get(a)! + radii.get(b)! + CLUSTER_SEPARATION_GAP;
        if (dist >= minSeparation) continue;
        if (dist < 0.001) {
          const angle = this.jitterRandom() * 2 * Math.PI;
          dx = Math.cos(angle);
          dy = Math.sin(angle);
          dist = 1.0;
        }
        const pushX = (dx / dist) * ((minSeparation - dist) / 2);
        const pushY = (dy / dist) * ((minSeparation - dist) / 2);
        for (const id of byCluster.get(a)!) {
          const n = this.nodes.get(id)!;
          n.x -= pushX;
          n.y -= pushY;
        }
        for (const id of byCluster.get(b)!) {
          const n = this.nodes.get(id)!;
          n.x += pushX;
          n.y += pushY;
        }
      }
    }
  }
}
