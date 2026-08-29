import React, { useMemo } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useTopicMap } from '../../hooks/useTopicMap';
import { computeTopicMapLayout, colorForCluster } from '../../lib/topicMapLayout';

export const TopicMapPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const { map, isStale, loading, error } = useTopicMap(courseId);

  const layout = useMemo(() => (map ? computeTopicMapLayout(map) : null), [map]);

  const bounds = useMemo(() => {
    if (!layout || layout.nodes.length === 0) return { minX: -200, minY: -200, maxX: 200, maxY: 200 };
    const xs = layout.nodes.map((n) => n.x);
    const ys = layout.nodes.map((n) => n.y);
    const pad = 60;
    return {
      minX: Math.min(...xs) - pad,
      minY: Math.min(...ys) - pad,
      maxX: Math.max(...xs) + pad,
      maxY: Math.max(...ys) + pad,
    };
  }, [layout]);

  const nodeById = useMemo(() => new Map(layout?.nodes.map((n) => [n.id, n]) ?? []), [layout]);

  return (
    <div>
      <Link to={`/courses/${courseId}`}>← Back to course</Link>
      <h1>Topic map</h1>

      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}
      {isStale && <p className="status-banner">This map may be out of date — new lectures were added since it was last built.</p>}
      {!loading && map && layout && layout.nodes.length === 0 && <p>No topics mapped yet.</p>}

      {layout && layout.nodes.length > 0 && (
        <>
          <svg
            viewBox={`${bounds.minX} ${bounds.minY} ${bounds.maxX - bounds.minX} ${bounds.maxY - bounds.minY}`}
            className="topic-map-svg"
            role="img"
            aria-label="Topic map"
          >
            {layout.edges.map((edge, i) => {
              const source = nodeById.get(edge.source);
              const target = nodeById.get(edge.target);
              if (!source || !target) return null;
              return (
                <line
                  key={i}
                  x1={source.x}
                  y1={source.y}
                  x2={target.x}
                  y2={target.y}
                  className="topic-map-edge"
                />
              );
            })}
            {layout.nodes.map((node) => (
              <g key={node.id} transform={`translate(${node.x}, ${node.y})`}>
                <circle
                  r={node.kind === 'ghost' ? 8 : 14}
                  fill={colorForCluster(node.clusterId, layout.clusterIds)}
                  opacity={node.kind === 'ghost' ? 0.4 : 1}
                  stroke="white"
                  strokeWidth={2}
                />
                <text y={node.kind === 'ghost' ? 22 : 28} textAnchor="middle" className="topic-map-label">
                  {node.label}
                </text>
              </g>
            ))}
          </svg>

          <ul className="topic-map-legend">
            {map!.clusters.map((cluster) => (
              <li key={cluster.cluster_id}>
                <span
                  className="course-color-dot"
                  style={{ backgroundColor: colorForCluster(cluster.cluster_id, layout.clusterIds) }}
                />
                {cluster.name}
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
};
