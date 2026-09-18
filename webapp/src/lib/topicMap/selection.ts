/**
 * user_interface/lib/presentation/widgets/topic_map/cluster_view/cluster_selection.dart のTS移植。
 * 何も選んでいなければCluster View、レクチャー番号を選べばLecture View、
 * ノードを選べばTopic View。
 */
import type { TopicMapData } from '../../types/content';

export type ClusterSelection =
  | { type: 'node'; id: string }
  | { type: 'cluster'; id: string }
  | { type: 'lecture'; id: string };

export type TopicMapViewMode = 'cluster' | 'lecture' | 'topic';

export function viewModeForSelection(selection: ClusterSelection | null): TopicMapViewMode {
  if (!selection) return 'cluster';
  switch (selection.type) {
    case 'lecture':
      return 'lecture';
    case 'node':
      return 'topic';
    case 'cluster':
      return 'cluster';
  }
}

export function selectionsEqual(a: ClusterSelection | null, b: ClusterSelection | null): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  return a.type === b.type && a.id === b.id;
}

export interface HighlightSet {
  nodeIds: Set<string>;
  edgeIndexes: Set<number>;
}

const EMPTY_HIGHLIGHT: HighlightSet = { nodeIds: new Set(), edgeIndexes: new Set() };

export function computeHighlight(
  data: TopicMapData,
  selection: ClusterSelection | null,
  clusterIdByNodeId: Map<string, string | null>,
  lectureNumByNodeId: Map<string, number>
): HighlightSet {
  if (!selection) return EMPTY_HIGHLIGHT;

  if (selection.type === 'node') {
    const nodeIds = new Set<string>([selection.id]);
    const edgeIndexes = new Set<number>();
    data.edges.forEach((edge, i) => {
      if (edge.source_id === selection.id || edge.target_id === selection.id) {
        edgeIndexes.add(i);
        nodeIds.add(edge.source_id);
        nodeIds.add(edge.target_id);
      }
    });
    return { nodeIds, edgeIndexes };
  }

  if (selection.type === 'lecture') {
    const lectureNum = Number(selection.id);
    const nodeIds = new Set<string>();
    for (const [nodeId, num] of lectureNumByNodeId.entries()) {
      if (num === lectureNum) nodeIds.add(nodeId);
    }
    const edgeIndexes = new Set<number>();
    data.edges.forEach((edge, i) => {
      if (lectureNumByNodeId.get(edge.source_id) === lectureNum || lectureNumByNodeId.get(edge.target_id) === lectureNum) {
        edgeIndexes.add(i);
      }
    });
    return { nodeIds, edgeIndexes };
  }

  const clusterId = selection.id;
  const nodeIds = new Set<string>();
  for (const [nodeId, cid] of clusterIdByNodeId.entries()) {
    if (cid === clusterId) nodeIds.add(nodeId);
  }
  const edgeIndexes = new Set<number>();
  data.edges.forEach((edge, i) => {
    if (clusterIdByNodeId.get(edge.source_id) === clusterId || clusterIdByNodeId.get(edge.target_id) === clusterId) {
      edgeIndexes.add(i);
    }
  });
  return { nodeIds, edgeIndexes };
}

export function buildClusterIdByNodeId(data: TopicMapData): Map<string, string | null> {
  const map = new Map<string, string | null>();
  for (const n of data.nodes) map.set(n.topic_id, n.cluster_id ?? null);
  for (const g of data.ghost_nodes) map.set(g.ghost_id, g.cluster_id ?? null);
  return map;
}
