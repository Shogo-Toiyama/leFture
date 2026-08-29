import { forceCenter, forceLink, forceManyBody, forceSimulation, type SimulationNodeDatum } from 'd3-force';
import type { TopicMapData } from '../types/content';

export interface LaidOutNode extends SimulationNodeDatum {
  id: string;
  label: string;
  clusterId: string;
  kind: 'topic' | 'ghost';
  x: number;
  y: number;
}

export interface LaidOutEdge {
  source: string;
  target: string;
  relationType: string;
}

export interface TopicMapLayout {
  nodes: LaidOutNode[];
  edges: LaidOutEdge[];
  clusterIds: string[];
}

/**
 * user_interface/lib/presentation/widgets/topic_map/force_layout/graph_force_simulation.dart
 * のTS簡略移植。座標はサーバー側に保存されていない(map jsonbはグラフ構造のみ)ため、
 * クライアント側でforce-directedレイアウトを毎回計算する。
 * 同一clusterのノードを弱く中心へ引き寄せるカスタムforceだけモバイル版の
 * 「クラスタごとの塊」表現を簡易再現し、凸包ブロブ描画は省略している。
 */
export function computeTopicMapLayout(map: TopicMapData): TopicMapLayout {
  const nodes: LaidOutNode[] = [
    ...map.nodes.map((n) => ({
      id: n.topic_id,
      label: n.title,
      clusterId: n.cluster_id,
      kind: 'topic' as const,
      x: 0,
      y: 0,
    })),
    ...map.ghost_nodes
      .filter((g) => g.status === 'active')
      .map((g) => ({
        id: g.ghost_id,
        label: g.name,
        clusterId: g.cluster_id,
        kind: 'ghost' as const,
        x: 0,
        y: 0,
      })),
  ];

  const nodeIds = new Set(nodes.map((n) => n.id));
  const edges = map.edges.filter((e) => nodeIds.has(e.source_id) && nodeIds.has(e.target_id));

  if (nodes.length === 0) {
    return { nodes: [], edges: [], clusterIds: map.clusters.map((c) => c.cluster_id) };
  }

  function clusterAttraction(strength: number) {
    return (alpha: number) => {
      const centroids = new Map<string, { x: number; y: number; count: number }>();
      for (const n of nodes) {
        const c = centroids.get(n.clusterId) ?? { x: 0, y: 0, count: 0 };
        c.x += n.x ?? 0;
        c.y += n.y ?? 0;
        c.count += 1;
        centroids.set(n.clusterId, c);
      }
      for (const c of centroids.values()) {
        c.x /= c.count;
        c.y /= c.count;
      }
      for (const n of nodes) {
        const c = centroids.get(n.clusterId)!;
        n.vx = (n.vx ?? 0) + (c.x - (n.x ?? 0)) * strength * alpha;
        n.vy = (n.vy ?? 0) + (c.y - (n.y ?? 0)) * strength * alpha;
      }
    };
  }

  const simulation = forceSimulation(nodes)
    .force(
      'link',
      forceLink(edges.map((e) => ({ source: e.source_id, target: e.target_id })))
        .id((d) => (d as LaidOutNode).id)
        .distance(90)
    )
    .force('charge', forceManyBody().strength(-220))
    .force('center', forceCenter(0, 0))
    .force('cluster', clusterAttraction(0.06))
    .stop();

  for (let i = 0; i < 300; i++) simulation.tick();

  return {
    nodes: nodes.map((n) => ({ ...n, x: n.x ?? 0, y: n.y ?? 0 })),
    edges: edges.map((e) => ({ source: e.source_id, target: e.target_id, relationType: e.relation_type })),
    clusterIds: map.clusters.map((c) => c.cluster_id),
  };
}

const CLUSTER_COLORS = ['#ffb300', '#5b8def', '#ff6b6b', '#20c997', '#a56cc1', '#ff922b', '#12b886', '#845ef7'];

export function colorForCluster(clusterId: string, clusterIds: string[]): string {
  const idx = clusterIds.indexOf(clusterId);
  return CLUSTER_COLORS[idx % CLUSTER_COLORS.length] ?? '#999';
}
