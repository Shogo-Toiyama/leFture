/**
 * cluster_map_view.dart の initState/_normalizeSettledPositions のTS移植。
 * シミュレーションを収束まで走らせ、その実測バウンディングボックス(+余白)で
 * キャンバスサイズを決め、原点(0,0)開始になるよう全ノードをシフトする。
 */
import type { TopicMapData } from '../../types/content';
import { GraphForceSimulation } from './force';
import { buildClusterIdByNodeId } from './selection';

const SIMULATION_SEED_BOUNDS = { width: 1100, height: 1400 };
/** kClusterBlobPadding(46) + ラベル分の余白。cluster_map_view.dart の _kContentPadding。 */
const CONTENT_PADDING = 160;

export interface TopicMapLayoutResult {
  simulation: GraphForceSimulation;
  canvasSize: { width: number; height: number };
  clusterIdByNodeId: Map<string, string | null>;
  lectureNumByNodeId: Map<string, number>;
}

export function computeTopicMapLayout(data: TopicMapData, lectureNumBySourceLectureId: Map<string, number>): TopicMapLayoutResult {
  const clusterIdByNodeId = buildClusterIdByNodeId(data);
  const lectureNumByNodeId = new Map<string, number>();
  for (const n of data.nodes) {
    const num = lectureNumBySourceLectureId.get(n.source_lecture_id);
    if (num !== undefined) lectureNumByNodeId.set(n.topic_id, num);
  }

  const nodeIds = [...data.nodes.map((n) => n.topic_id), ...data.ghost_nodes.map((g) => g.ghost_id)];
  const edgePairs = [
    ...data.edges.map((e) => ({ source: e.source_id, target: e.target_id })),
    ...data.ghost_nodes
      .filter((g) => g.derived_from_topic_id)
      .map((g) => ({ source: g.derived_from_topic_id as string, target: g.ghost_id })),
  ];

  const simulation = new GraphForceSimulation({
    nodeIds,
    clusterIdByNodeId,
    edgePairs,
    clusterOrder: data.clusters.map((c) => c.cluster_id),
    bounds: SIMULATION_SEED_BOUNDS,
  });
  simulation.runToConvergence();

  const canvasSize = normalizeSettledPositions(simulation);

  return { simulation, canvasSize, clusterIdByNodeId, lectureNumByNodeId };
}

function normalizeSettledPositions(simulation: GraphForceSimulation): { width: number; height: number } {
  const positions = Array.from(simulation.nodes.values());
  if (positions.length === 0) return SIMULATION_SEED_BOUNDS;

  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const p of positions) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }

  const shiftX = -minX + CONTENT_PADDING;
  const shiftY = -minY + CONTENT_PADDING;
  for (const node of simulation.nodes.values()) {
    node.x += shiftX;
    node.y += shiftY;
  }

  return {
    width: maxX - minX + CONTENT_PADDING * 2,
    height: maxY - minY + CONTENT_PADDING * 2,
  };
}
