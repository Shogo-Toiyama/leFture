import type { TopicMapData } from '../../types/content';
import type { GraphForceSimulation } from './force';
import { buildClusterBlob, type ClusterBlobShape } from './geometry';
import { CLUSTER_BLOB_PADDING } from './style';

/** cluster_geometry.dart の computeClusterBlobs のTS移植。 */
export function computeClusterBlobs(
  data: TopicMapData,
  simulation: GraphForceSimulation,
  padding: number = CLUSTER_BLOB_PADDING
): Map<string, ClusterBlobShape> {
  const pointsByCluster = new Map<string, { x: number; y: number }[]>();

  const addPoint = (clusterId: string | null | undefined, nodeId: string) => {
    if (!clusterId) return;
    const position = simulation.nodes.get(nodeId);
    if (!position) return;
    if (!pointsByCluster.has(clusterId)) pointsByCluster.set(clusterId, []);
    pointsByCluster.get(clusterId)!.push({ x: position.x, y: position.y });
  };

  for (const node of data.nodes) addPoint(node.cluster_id, node.topic_id);
  for (const ghost of data.ghost_nodes) addPoint(ghost.cluster_id, ghost.ghost_id);

  const result = new Map<string, ClusterBlobShape>();
  for (const [clusterId, points] of pointsByCluster.entries()) {
    result.set(clusterId, buildClusterBlob(points, padding));
  }
  return result;
}
