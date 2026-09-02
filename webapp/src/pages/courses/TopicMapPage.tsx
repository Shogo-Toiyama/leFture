import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useTopicMap } from '../../hooks/useTopicMap';
import { computeTopicMapLayout, colorForCluster } from '../../lib/topicMapLayout';
import { apiFetch } from '../../lib/api';
import { PageState } from '../../components/PageState';

interface Viewport {
  scale: number;
  tx: number;
  ty: number;
}

const MIN_SCALE = 0.3;
const MAX_SCALE = 3;

export const TopicMapPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { map, isStale, loading, error } = useTopicMap(courseId);
  const svgRef = useRef<SVGSVGElement>(null);

  const [viewport, setViewport] = useState<Viewport>({ scale: 1, tx: 0, ty: 0 });
  const [hovered, setHovered] = useState<string | null>(null);
  const [rebuilding, setRebuilding] = useState(false);
  const dragState = useRef<{ x: number; y: number; tx: number; ty: number } | null>(null);

  const layout = useMemo(() => (map ? computeTopicMapLayout(map) : null), [map]);
  const nodeById = useMemo(() => new Map(layout?.nodes.map((n) => [n.id, n]) ?? []), [layout]);

  // レイアウト計算後、グラフ全体が画面に収まる初期倍率・位置に合わせる。
  useEffect(() => {
    const svg = svgRef.current;
    if (!layout || layout.nodes.length === 0 || !svg) return;
    const xs = layout.nodes.map((n) => n.x);
    const ys = layout.nodes.map((n) => n.y);
    const pad = 80;
    const width = Math.max(...xs) - Math.min(...xs) + pad * 2;
    const height = Math.max(...ys) - Math.min(...ys) + pad * 2;
    const box = svg.getBoundingClientRect();
    const scale = Math.min(Math.min(box.width / width, box.height / height), 1.4);
    const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
    const cy = (Math.min(...ys) + Math.max(...ys)) / 2;
    setViewport({ scale, tx: box.width / 2 - cx * scale, ty: box.height / 2 - cy * scale });
  }, [layout]);

  const handleWheel = useCallback((event: React.WheelEvent<SVGSVGElement>) => {
    event.preventDefault();
    const svg = event.currentTarget.getBoundingClientRect();
    const px = event.clientX - svg.left;
    const py = event.clientY - svg.top;
    setViewport((prev) => {
      const factor = event.deltaY < 0 ? 1.12 : 1 / 1.12;
      const scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, prev.scale * factor));
      const ratio = scale / prev.scale;
      return { scale, tx: px - (px - prev.tx) * ratio, ty: py - (py - prev.ty) * ratio };
    });
  }, []);

  const handlePointerDown = (event: React.PointerEvent<SVGSVGElement>) => {
    if (event.button !== 0) return;
    (event.target as Element).setPointerCapture?.(event.pointerId);
    dragState.current = { x: event.clientX, y: event.clientY, tx: viewport.tx, ty: viewport.ty };
  };

  const handlePointerMove = (event: React.PointerEvent<SVGSVGElement>) => {
    const drag = dragState.current;
    if (!drag) return;
    setViewport((prev) => ({
      ...prev,
      tx: drag.tx + (event.clientX - drag.x),
      ty: drag.ty + (event.clientY - drag.y),
    }));
  };

  const endDrag = () => {
    dragState.current = null;
  };

  const rebuild = async () => {
    if (!courseId) return;
    setRebuilding(true);
    try {
      await apiFetch('/topic-map/reconstruct', {
        method: 'POST',
        body: JSON.stringify({ course_id: courseId }),
      });
      window.location.reload();
    } finally {
      setRebuilding(false);
    }
  };

  if (loading) return <PageState kind="loading" />;
  if (error) return <PageState kind="error" message={error} />;
  if (!layout || layout.nodes.length === 0) {
    return (
      <PageState
        kind="empty"
        title="No topic map yet"
        message="The topic map is built once lectures in this course finish processing."
        action={<Link to={`/courses/${courseId}`}>Back to course</Link>}
      />
    );
  }

  const hoveredNode = hovered ? nodeById.get(hovered) : null;

  return (
    <div className="map-page">
      <header className="page-header">
        <div>
          <Link to={`/courses/${courseId}`} className="back-link">
            ← Course
          </Link>
          <h1>Topic map</h1>
        </div>
        <div className="page-header-actions">
          {isStale && (
            <button type="button" onClick={rebuild} disabled={rebuilding}>
              {rebuilding ? 'Rebuilding…' : 'Rebuild map'}
            </button>
          )}
          <button type="button" className="ghost" onClick={() => setViewport((v) => ({ ...v, scale: v.scale * 1.15 }))}>
            +
          </button>
          <button type="button" className="ghost" onClick={() => setViewport((v) => ({ ...v, scale: v.scale / 1.15 }))}>
            −
          </button>
        </div>
      </header>

      {isStale && (
        <p className="notice">This map may be out of date — lectures changed since it was last built.</p>
      )}

      <div className="map-canvas-wrap">
        <svg
          ref={svgRef}
          className="topic-map-svg"
          role="img"
          aria-label="Topic map"
          onWheel={handleWheel}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={endDrag}
          onPointerLeave={endDrag}
        >
          <g transform={`translate(${viewport.tx}, ${viewport.ty}) scale(${viewport.scale})`}>
            {layout.edges.map((edge, i) => {
              const source = nodeById.get(edge.source);
              const target = nodeById.get(edge.target);
              if (!source || !target) return null;
              const isTouched = hovered === edge.source || hovered === edge.target;
              return (
                <line
                  key={i}
                  x1={source.x}
                  y1={source.y}
                  x2={target.x}
                  y2={target.y}
                  className={`topic-map-edge ${isTouched ? 'is-active' : ''}`}
                />
              );
            })}

            {layout.nodes.map((node) => {
              const radius = node.kind === 'ghost' ? 7 : 13;
              const color = colorForCluster(node.clusterId, layout.clusterIds);
              return (
                <g
                  key={node.id}
                  transform={`translate(${node.x}, ${node.y})`}
                  className={`topic-map-node ${hovered === node.id ? 'is-hovered' : ''}`}
                  onMouseEnter={() => setHovered(node.id)}
                  onMouseLeave={() => setHovered((prev) => (prev === node.id ? null : prev))}
                  onClick={() => {
                    const source = map?.nodes.find((n) => n.topic_id === node.id);
                    if (source) navigate(`/lectures/${source.source_lecture_id}`);
                  }}
                >
                  <circle r={radius + 5} className="topic-map-node-halo" fill={color} />
                  <circle r={radius} fill={color} opacity={node.kind === 'ghost' ? 0.45 : 1} />
                  <text y={radius + 15} textAnchor="middle" className="topic-map-label">
                    {node.label.length > 26 ? `${node.label.slice(0, 25)}…` : node.label}
                  </text>
                </g>
              );
            })}
          </g>
        </svg>

        {hoveredNode && (
          <div className="map-hint">
            <strong>{hoveredNode.label}</strong>
            <span>{hoveredNode.kind === 'ghost' ? 'Related concept' : 'Click to open lecture'}</span>
          </div>
        )}
      </div>

      <ul className="topic-map-legend">
        {map!.clusters.map((cluster) => (
          <li key={cluster.cluster_id}>
            <span
              className="dot"
              style={{ backgroundColor: colorForCluster(cluster.cluster_id, layout.clusterIds) }}
            />
            {cluster.name}
          </li>
        ))}
      </ul>
    </div>
  );
};
