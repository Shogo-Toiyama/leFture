import React, {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react';
import type { TopicMapData } from '../../../types/content';
import { GraphForceSimulation } from '../../../lib/topicMap/force';
import { computeClusterBlobs } from '../../../lib/topicMap/blobs';
import { clusterBlobCenter, clusterBlobOutsideTopAnchor, type ClusterBlobShape } from '../../../lib/topicMap/geometry';
import { computeHighlight, viewModeForSelection, type ClusterSelection } from '../../../lib/topicMap/selection';
import {
  CLUSTER_CENTER_LABEL_MAX_SCALE,
  GHOST_NODE_RADIUS,
  NODE_RADIUS,
  RELATION_LABEL_MIN_SCALE,
  clusterColor,
  clusterLabelGrowFactor,
  detailShrinkFactor,
} from '../../../lib/topicMap/style';
import { wrapLabel } from '../../../lib/topicMap/wrapLabel';

const MIN_SCALE_FLOOR = 0.3;
const MAX_SCALE = 2.5;
const LECTURE_FIT_MS = 460;

interface Bounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface TopicMapCanvasHandle {
  focusLecture: (lectureNum: number) => void;
  resetView: () => void;
  zoomBy: (factor: number) => void;
}

interface TopicMapCanvasProps {
  data: TopicMapData;
  simulation: GraphForceSimulation;
  canvasSize: { width: number; height: number };
  clusterIdByNodeId: Map<string, string | null>;
  lectureNumByNodeId: Map<string, number>;
  selection: ClusterSelection | null;
  onSelectNode: (nodeId: string) => void;
  onSelectCluster: (clusterId: string) => void;
  onClearSelection: () => void;
}

export const TopicMapCanvas = forwardRef<TopicMapCanvasHandle, TopicMapCanvasProps>(function TopicMapCanvas(
  {
    data,
    simulation,
    canvasSize,
    clusterIdByNodeId,
    lectureNumByNodeId,
    selection,
    onSelectNode,
    onSelectCluster,
    onClearSelection,
  },
  ref
) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [viewport, setViewport] = useState({ width: 0, height: 0 });
  const [transform, setTransform] = useState({ scale: 1, tx: 0, ty: 0 });
  const [animated, setAnimated] = useState(false);
  const hasFitOnce = useRef(false);
  const dragState = useRef<{ x: number; y: number; tx: number; ty: number; moved: boolean } | null>(null);
  const suppressNextClick = useRef(false);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const box = entries[0]?.contentRect;
      if (box) setViewport({ width: box.width, height: box.height });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const fitScale = useCallback(
    (vw: number, vh: number) => {
      if (vw <= 0 || vh <= 0 || canvasSize.width <= 0 || canvasSize.height <= 0) return 1;
      return Math.min(vw / canvasSize.width, vh / canvasSize.height) * 0.92;
    },
    [canvasSize]
  );

  const effectiveMinScale = useCallback((vw: number, vh: number) => Math.min(MIN_SCALE_FLOOR, fitScale(vw, vh)), [fitScale]);

  const matrixForBounds = useCallback(
    (bounds: Bounds, vw: number, vh: number, scaleOverride?: number) => {
      const boundsW = bounds.maxX - bounds.minX;
      const boundsH = bounds.maxY - bounds.minY;
      const rawScale = scaleOverride ?? (boundsW <= 0 || boundsH <= 0 ? 1 : Math.min(vw / boundsW, vh / boundsH) * 0.85);
      const scale = Math.min(MAX_SCALE, Math.max(effectiveMinScale(vw, vh), rawScale));
      const cx = (bounds.minX + bounds.maxX) / 2;
      const cy = (bounds.minY + bounds.maxY) / 2;
      return { scale, tx: vw / 2 - cx * scale, ty: vh / 2 - cy * scale };
    },
    [effectiveMinScale]
  );

  // Cluster View全体が収まる初期表示。マウント後、実寸のviewportが分かった最初の一回だけ。
  useEffect(() => {
    if (hasFitOnce.current) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;
    hasFitOnce.current = true;
    const scale = fitScale(viewport.width, viewport.height);
    setTransform(
      matrixForBounds({ minX: 0, minY: 0, maxX: canvasSize.width, maxY: canvasSize.height }, viewport.width, viewport.height, scale)
    );
  }, [viewport, canvasSize, fitScale, matrixForBounds]);

  const focusLecture = useCallback(
    (lectureNum: number) => {
      if (viewport.width <= 0 || viewport.height <= 0) return;
      let minX = Infinity;
      let minY = Infinity;
      let maxX = -Infinity;
      let maxY = -Infinity;
      let found = false;
      for (const [nodeId, num] of lectureNumByNodeId.entries()) {
        if (num !== lectureNum) continue;
        const pos = simulation.nodes.get(nodeId);
        if (!pos) continue;
        found = true;
        minX = Math.min(minX, pos.x);
        minY = Math.min(minY, pos.y);
        maxX = Math.max(maxX, pos.x);
        maxY = Math.max(maxY, pos.y);
      }
      if (!found) return;
      const pad = NODE_RADIUS + 60;
      setAnimated(true);
      setTransform(
        matrixForBounds(
          { minX: minX - pad, minY: minY - pad, maxX: maxX + pad, maxY: maxY + pad },
          viewport.width,
          viewport.height
        )
      );
      window.setTimeout(() => setAnimated(false), LECTURE_FIT_MS);
    },
    [lectureNumByNodeId, simulation, viewport, matrixForBounds]
  );

  const resetView = useCallback(() => {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    setAnimated(true);
    setTransform(
      matrixForBounds(
        { minX: 0, minY: 0, maxX: canvasSize.width, maxY: canvasSize.height },
        viewport.width,
        viewport.height,
        fitScale(viewport.width, viewport.height)
      )
    );
    window.setTimeout(() => setAnimated(false), LECTURE_FIT_MS);
  }, [viewport, canvasSize, matrixForBounds, fitScale]);

  const zoomBy = useCallback(
    (factor: number) => {
      const minScale = effectiveMinScale(viewport.width, viewport.height);
      setTransform((prev) => {
        const scale = Math.min(MAX_SCALE, Math.max(minScale, prev.scale * factor));
        const ratio = scale / prev.scale;
        const cx = viewport.width / 2;
        const cy = viewport.height / 2;
        return { scale, tx: cx - (cx - prev.tx) * ratio, ty: cy - (cy - prev.ty) * ratio };
      });
    },
    [effectiveMinScale, viewport]
  );

  useImperativeHandle(ref, () => ({ focusLecture, resetView, zoomBy }), [focusLecture, resetView, zoomBy]);

  const handleWheel = useCallback(
    (e: React.WheelEvent<SVGSVGElement>) => {
      e.preventDefault();
      const rect = e.currentTarget.getBoundingClientRect();
      const px = e.clientX - rect.left;
      const py = e.clientY - rect.top;
      const minScale = effectiveMinScale(viewport.width, viewport.height);
      setTransform((prev) => {
        const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
        const scale = Math.min(MAX_SCALE, Math.max(minScale, prev.scale * factor));
        const ratio = scale / prev.scale;
        return { scale, tx: px - (px - prev.tx) * ratio, ty: py - (py - prev.ty) * ratio };
      });
    },
    [effectiveMinScale, viewport]
  );

  const handlePointerDown = (e: React.PointerEvent<SVGSVGElement>) => {
    if (e.button !== 0) return;
    (e.target as Element).setPointerCapture?.(e.pointerId);
    dragState.current = { x: e.clientX, y: e.clientY, tx: transform.tx, ty: transform.ty, moved: false };
  };

  const handlePointerMove = (e: React.PointerEvent<SVGSVGElement>) => {
    const drag = dragState.current;
    if (!drag) return;
    const dx = e.clientX - drag.x;
    const dy = e.clientY - drag.y;
    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) drag.moved = true;
    setTransform((prev) => ({ ...prev, tx: drag.tx + dx, ty: drag.ty + dy }));
  };

  const endDrag = () => {
    if (dragState.current?.moved) suppressNextClick.current = true;
    dragState.current = null;
  };

  const guardClick = useCallback((handler: () => void) => {
    return (e: React.MouseEvent) => {
      e.stopPropagation();
      if (suppressNextClick.current) {
        suppressNextClick.current = false;
        return;
      }
      handler();
    };
  }, []);

  const highlight = useMemo(
    () => computeHighlight(data, selection, clusterIdByNodeId, lectureNumByNodeId),
    [data, selection, clusterIdByNodeId, lectureNumByNodeId]
  );
  const viewMode = viewModeForSelection(selection);
  const blobs = useMemo(() => computeClusterBlobs(data, simulation), [data, simulation]);
  const ghostNodeIds = useMemo(() => new Set(data.ghost_nodes.map((g) => g.ghost_id)), [data]);
  const clusterColorById = useMemo(() => {
    const map = new Map<string, string>();
    data.clusters.forEach((c, i) => map.set(c.cluster_id, clusterColor(i)));
    return map;
  }, [data.clusters]);

  const currentScale = transform.scale;
  const shrink = detailShrinkFactor(currentScale);
  const showRelationLabels = currentScale >= RELATION_LABEL_MIN_SCALE;

  const radiusFor = (nodeId: string) => (ghostNodeIds.has(nodeId) ? GHOST_NODE_RADIUS : NODE_RADIUS) * shrink;

  const isGlowing = (nodeId: string) => {
    if (viewMode === 'topic') return selection?.type === 'node' && selection.id === nodeId;
    if (viewMode === 'lecture') return highlight.nodeIds.has(nodeId);
    return false;
  };

  const nodeOpacity = (nodeId: string, isGhost: boolean) => {
    const base = isGhost ? 0.55 : 0.55;
    const highlightOpacity = isGhost ? 0.85 : 1.0;
    if (!selection) return base;
    if (viewMode === 'lecture') return highlight.nodeIds.has(nodeId) ? highlightOpacity : base;
    if (highlight.nodeIds.has(nodeId)) return highlightOpacity;
    return viewMode === 'topic' ? 0.35 : 0.1;
  };

  const edgeOpacity = (isHighlighted: boolean) => {
    if (!selection) return 0.4;
    if (viewMode === 'lecture') return isHighlighted ? 0.95 : 0.4;
    if (isHighlighted) return 0.95;
    return viewMode === 'topic' ? 0.3 : 0.08;
  };

  const blobFillStroke = (clusterId: string) => {
    const isSelectedCluster = selection?.type === 'cluster' && selection.id === clusterId;
    const isAnyClusterSelected = selection?.type === 'cluster';
    const fillAlpha = isSelectedCluster ? 0.2 : isAnyClusterSelected ? 0.04 : 0.08;
    const strokeAlpha = isSelectedCluster ? 0.65 : isAnyClusterSelected ? 0.18 : 0.38;
    return { fillAlpha, strokeAlpha, strokeWidth: isSelectedCluster ? 2.4 : 1.6 };
  };

  const hexToRgba = (hex: string, alpha: number) => {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!m) return hex;
    const r = parseInt(m[1], 16);
    const g = parseInt(m[2], 16);
    const b = parseInt(m[3], 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  };

  const renderBlob = (clusterId: string, blob: ClusterBlobShape) => {
    const color = clusterColorById.get(clusterId) ?? '#8e99a6';
    const { fillAlpha, strokeAlpha, strokeWidth } = blobFillStroke(clusterId);
    const fill = hexToRgba(color, fillAlpha);
    const stroke = hexToRgba(color, strokeAlpha);
    const onClick = guardClick(() => onSelectCluster(clusterId));

    if (blob.kind === 'circle') {
      return (
        <circle
          key={clusterId}
          cx={blob.center.x}
          cy={blob.center.y}
          r={blob.radius}
          fill={fill}
          stroke={stroke}
          strokeWidth={strokeWidth}
          className="tm-cluster-blob"
          onClick={onClick}
        />
      );
    }
    if (blob.kind === 'capsule') {
      return (
        <line
          key={clusterId}
          x1={blob.start.x}
          y1={blob.start.y}
          x2={blob.end.x}
          y2={blob.end.y}
          stroke={fill}
          strokeWidth={blob.radius * 2}
          strokeLinecap="round"
          className="tm-cluster-blob"
          onClick={onClick}
        />
      );
    }
    return (
      <path
        key={clusterId}
        d={blob.d}
        fill={fill}
        stroke={stroke}
        strokeWidth={strokeWidth}
        className="tm-cluster-blob"
        onClick={onClick}
      />
    );
  };

  return (
    <div className="tm-canvas-wrap" ref={wrapRef}>
      <svg
        className="tm-svg"
        width={viewport.width}
        height={viewport.height}
        onWheel={handleWheel}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={endDrag}
        onPointerLeave={endDrag}
        role="img"
        aria-label="Topic map"
      >
        <g
          transform={`translate(${transform.tx}, ${transform.ty}) scale(${transform.scale})`}
          style={{ transition: animated ? `transform ${LECTURE_FIT_MS}ms cubic-bezier(0.65, 0, 0.35, 1)` : 'none' }}
        >
          <rect
            x={-20000}
            y={-20000}
            width={40000}
            height={40000}
            fill="transparent"
            onClick={guardClick(onClearSelection)}
          />

          {Array.from(blobs.entries()).map(([clusterId, blob]) => renderBlob(clusterId, blob))}

          {/* ゴースト由来エッジ (derived_from_topic_id を破線で結ぶ) */}
          {data.ghost_nodes.map((ghost) => {
            const sourceId = ghost.derived_from_topic_id;
            if (!sourceId) return null;
            const from = simulation.nodes.get(sourceId);
            const to = simulation.nodes.get(ghost.ghost_id);
            if (!from || !to) return null;
            const dx = to.x - from.x;
            const dy = to.y - from.y;
            const dist = Math.hypot(dx, dy);
            if (dist < 0.001) return null;
            const ux = dx / dist;
            const uy = dy / dist;
            const startX = from.x + ux * radiusFor(sourceId);
            const startY = from.y + uy * radiusFor(sourceId);
            const endX = to.x - ux * radiusFor(ghost.ghost_id);
            const endY = to.y - uy * radiusFor(ghost.ghost_id);
            const isHighlighted = highlight.nodeIds.has(sourceId) || highlight.nodeIds.has(ghost.ghost_id);
            const opacity = edgeOpacity(isHighlighted) * 0.85;
            return (
              <line
                key={`ghost-edge-${ghost.ghost_id}`}
                x1={startX}
                y1={startY}
                x2={endX}
                y2={endY}
                className="tm-ghost-edge"
                strokeWidth={1.6 * shrink * 0.85}
                strokeOpacity={opacity}
                strokeDasharray={`${5 * shrink} ${4 * shrink}`}
              />
            );
          })}

          {/* 実エッジ */}
          {data.edges.map((edge, i) => {
            const from = simulation.nodes.get(edge.source_id);
            const to = simulation.nodes.get(edge.target_id);
            if (!from || !to) return null;
            const dx = to.x - from.x;
            const dy = to.y - from.y;
            const dist = Math.hypot(dx, dy);
            if (dist < 0.001) return null;
            const ux = dx / dist;
            const uy = dy / dist;
            const startX = from.x + ux * radiusFor(edge.source_id);
            const startY = from.y + uy * radiusFor(edge.source_id);
            const endX = to.x - ux * radiusFor(edge.target_id);
            const endY = to.y - uy * radiusFor(edge.target_id);
            const opacity = edgeOpacity(highlight.edgeIndexes.has(i));
            const arrowLen = 10 * shrink;
            const arrowW = 7 * shrink;
            const backX = endX - ux * arrowLen;
            const backY = endY - uy * arrowLen;
            const nx = -uy * (arrowW / 2);
            const ny = ux * (arrowW / 2);
            const angle = (Math.atan2(dy, dx) * 180) / Math.PI;
            const labelMidX = (startX + endX) / 2;
            const labelMidY = (startY + endY) / 2;
            const [line1, line2] = showRelationLabels ? wrapLabel(edge.relation_type.replace(/_/g, ' '), 22) : [''];
            return (
              <g key={`edge-${i}`}>
                <line x1={startX} y1={startY} x2={endX} y2={endY} className="tm-edge" strokeWidth={1.6 * shrink} strokeOpacity={opacity} />
                <polygon
                  points={`${endX},${endY} ${backX + nx},${backY + ny} ${backX - nx},${backY - ny}`}
                  className="tm-edge-arrow"
                  fillOpacity={opacity}
                />
                {showRelationLabels && (
                  <g transform={`translate(${labelMidX}, ${labelMidY}) rotate(${angle > 90 || angle < -90 ? angle + 180 : angle})`}>
                    <rect
                      x={-40 * shrink}
                      y={-16 * shrink}
                      width={80 * shrink}
                      height={12 * shrink}
                      rx={4 * shrink}
                      className="tm-edge-label-bg"
                      fillOpacity={opacity * 0.9}
                    />
                    <text textAnchor="middle" y={-8 * shrink} className="tm-edge-label-text" fontSize={9.5 * shrink} fillOpacity={opacity}>
                      {line1}
                      {line2 ? ` ${line2}` : ''}
                    </text>
                  </g>
                )}
              </g>
            );
          })}

          {/* クラスタ名ラベル */}
          {data.clusters.map((cluster) => {
            const blob = blobs.get(cluster.cluster_id);
            if (!blob) return null;
            const color = clusterColorById.get(cluster.cluster_id) ?? '#8e99a6';
            const useCenterLabel = viewMode === 'cluster' && currentScale <= CLUSTER_CENTER_LABEL_MAX_SCALE;
            if (useCenterLabel) {
              const anchor = clusterBlobCenter(blob);
              const grow = clusterLabelGrowFactor(currentScale);
              return (
                <g key={`label-${cluster.cluster_id}`} transform={`translate(${anchor.x}, ${anchor.y})`}>
                  <rect
                    x={-95 * grow}
                    y={-14 * grow}
                    width={190 * grow}
                    height={28 * grow}
                    rx={14 * grow}
                    className="tm-cluster-center-label-bg"
                  />
                  <text textAnchor="middle" dominantBaseline="middle" fontSize={16 * grow} fontWeight={800} fill={color}>
                    {cluster.name}
                  </text>
                </g>
              );
            }
            const anchor = clusterBlobOutsideTopAnchor(blob);
            const [line1] = wrapLabel(cluster.name, 20);
            return (
              <g key={`label-${cluster.cluster_id}`} transform={`translate(${anchor.x}, ${anchor.y - 8})`}>
                <rect
                  x={-75 * shrink}
                  y={-11 * shrink}
                  width={150 * shrink}
                  height={22 * shrink}
                  rx={10 * shrink}
                  className="tm-cluster-outside-label-bg"
                  stroke={color}
                />
                <text textAnchor="middle" dominantBaseline="middle" fontSize={11 * shrink} fontWeight={700} fill={color}>
                  {line1}
                </text>
              </g>
            );
          })}

          {/* 実ノード */}
          {data.nodes.map((node) => {
            const pos = simulation.nodes.get(node.topic_id);
            if (!pos) return null;
            const color = clusterColorById.get(node.cluster_id) ?? '#8e99a6';
            const r = radiusFor(node.topic_id);
            const opacity = nodeOpacity(node.topic_id, false);
            const glowing = isGlowing(node.topic_id);
            const [line1, line2] = wrapLabel(node.title);
            return (
              <g
                key={node.topic_id}
                className="tm-node"
                transform={`translate(${pos.x}, ${pos.y})`}
                onClick={guardClick(() => onSelectNode(node.topic_id))}
              >
                {glowing && <circle r={r + 6 * shrink} className="tm-node-glow" />}
                <circle r={r} fill={color} fillOpacity={opacity} className="tm-node-circle" stroke="var(--void-deep)" strokeWidth={2.5 * shrink} />
                <text y={r + 12 * shrink} textAnchor="middle" fillOpacity={opacity} className="tm-node-label" fontSize={10 * shrink}>
                  {line1}
                </text>
                {line2 && (
                  <text y={r + 12 * shrink + 11 * shrink} textAnchor="middle" fillOpacity={opacity} className="tm-node-label" fontSize={10 * shrink}>
                    {line2}
                  </text>
                )}
              </g>
            );
          })}

          {/* ゴーストノード(未収録の予測トピック) */}
          {data.ghost_nodes.map((ghost) => {
            const pos = simulation.nodes.get(ghost.ghost_id);
            if (!pos) return null;
            const color = clusterColorById.get(ghost.cluster_id) ?? '#8e99a6';
            const r = radiusFor(ghost.ghost_id);
            const opacity = nodeOpacity(ghost.ghost_id, true) * (ghost.status === 'faded' ? 0.55 : 1);
            const glowing = isGlowing(ghost.ghost_id);
            const [line1, line2] = wrapLabel(ghost.name);
            return (
              <g
                key={ghost.ghost_id}
                className="tm-node is-ghost"
                transform={`translate(${pos.x}, ${pos.y})`}
                onClick={guardClick(() => onSelectNode(ghost.ghost_id))}
              >
                {glowing && <circle r={r + 6 * shrink} className="tm-node-glow" />}
                <circle
                  r={r}
                  fill={color}
                  fillOpacity={opacity * 0.18}
                  stroke={color}
                  strokeOpacity={opacity}
                  strokeWidth={1.8 * shrink}
                  strokeDasharray={`${3 * shrink} ${2.5 * shrink}`}
                  className="tm-node-circle is-ghost"
                />
                <text y={r + 12 * shrink} textAnchor="middle" fillOpacity={opacity} className="tm-node-label is-ghost" fontSize={10 * shrink}>
                  {line1}
                </text>
                {line2 && (
                  <text
                    y={r + 12 * shrink + 11 * shrink}
                    textAnchor="middle"
                    fillOpacity={opacity}
                    className="tm-node-label is-ghost"
                    fontSize={10 * shrink}
                  >
                    {line2}
                  </text>
                )}
              </g>
            );
          })}
        </g>
      </svg>
    </div>
  );
});
