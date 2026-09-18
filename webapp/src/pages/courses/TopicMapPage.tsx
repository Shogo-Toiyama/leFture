import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { RefreshCw, ZoomIn, ZoomOut } from 'lucide-react';
import { useTopicMap } from '../../hooks/useTopicMap';
import { useCourse } from '../../hooks/useCourse';
import { apiFetch } from '../../lib/api';
import { listLecturesByCreatedAt } from '../../lib/lectures';
import { listLectureTopics } from '../../lib/content';
import { lectureDisplayTitle } from '../../types/lecture';
import type { Lecture } from '../../types/lecture';
import { stripSidCitations } from '../../lib/sidCitation';
import { PageState } from '../../components/PageState';
import { TopicMapSkeleton } from '../../components/courses/TopicMapSkeleton';
import { TopicMapCanvas, type TopicMapCanvasHandle } from '../../components/courses/topicMap/TopicMapCanvas';
import { TopicMapDetailSheet, type TopicMapPanelData, type RelatedTopicEdge } from '../../components/courses/topicMap/TopicMapDetailSheet';
import { computeTopicMapLayout } from '../../lib/topicMap/layout';
import type { ClusterSelection } from '../../lib/topicMap/selection';
import { useLanguage } from '../../i18n/LanguageContext';

export const TopicMapPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { language, t } = useLanguage();
  const isJa = language === 'ja';

  const { map, isStale, loading, error } = useTopicMap(courseId);
  const { course } = useCourse(courseId);
  const canvasRef = useRef<TopicMapCanvasHandle>(null);

  const [rebuilding, setRebuilding] = useState(false);
  const [selection, setSelection] = useState<ClusterSelection | null>(null);
  const [lecturesByCreatedAt, setLecturesByCreatedAt] = useState<Lecture[]>([]);
  const [panelData, setPanelData] = useState<TopicMapPanelData | null>(null);
  const [panelLectureId, setPanelLectureId] = useState<string | null>(null);

  // マップページ限定: トラックパッドのピンチ操作でブラウザ全体の画面がズームするのを防止し、
  // マップキャンバスのズームに連動させる
  useEffect(() => {
    const handleWheel = (e: WheelEvent) => {
      if (e.ctrlKey) {
        // macOS等のトラックパッドピンチは ctrlKey=true の wheel イベント
        e.preventDefault();
        const factor = Math.exp(-e.deltaY * 0.01);
        canvasRef.current?.zoomBy(factor);
      }
    };

    const preventGesture = (e: Event) => {
      e.preventDefault();
    };

    window.addEventListener('wheel', handleWheel, { passive: false });
    window.addEventListener('gesturestart', preventGesture, { passive: false });
    window.addEventListener('gesturechange', preventGesture, { passive: false });
    window.addEventListener('gestureend', preventGesture, { passive: false });

    return () => {
      window.removeEventListener('wheel', handleWheel);
      window.removeEventListener('gesturestart', preventGesture);
      window.removeEventListener('gesturechange', preventGesture);
      window.removeEventListener('gestureend', preventGesture);
    };
  }, []);

  useEffect(() => {
    if (!courseId) return;
    let cancelled = false;
    listLecturesByCreatedAt(courseId)
      .then((list) => {
        if (!cancelled) setLecturesByCreatedAt(list);
      })
      .catch(() => {
        /* レクチャー番号の解決に失敗しても、地図自体は表示を続ける */
      });
    return () => {
      cancelled = true;
    };
  }, [courseId]);

  const lectureNumBySourceLectureId = useMemo(() => {
    const map = new Map<string, number>();
    lecturesByCreatedAt.forEach((lecture, i) => map.set(lecture.id, i + 1));
    return map;
  }, [lecturesByCreatedAt]);

  const layout = useMemo(() => {
    if (!map) return null;
    return computeTopicMapLayout(map, lectureNumBySourceLectureId);
  }, [map, lectureNumBySourceLectureId]);

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

  const selectedEntityLabel = useMemo(() => {
    if (!map || !selection) return null;
    if (selection.type === 'node') {
      const node = map.nodes.find((n) => n.topic_id === selection.id);
      if (node) return node.title;
      const ghost = map.ghost_nodes.find((g) => g.ghost_id === selection.id);
      return ghost?.name ?? null;
    }
    if (selection.type === 'lecture') {
      return isJa ? `講義 ${selection.id}` : `Lecture ${selection.id}`;
    }
    return map.clusters.find((c) => c.cluster_id === selection.id)?.name ?? null;
  }, [map, selection, isJa]);

  // ノード/レクチャー選択が変わるたびに、詳細シートの中身を解決する
  // (lecture_topic_detail_panel.dart の _loadPanelData 相当)。
  useEffect(() => {
    let cancelled = false;

    async function resolve() {
      if (!map || !selection || selection.type === 'cluster') {
        setPanelData(null);
        setPanelLectureId(null);
        return;
      }

      if (selection.type === 'lecture') {
        const lectureNum = Number(selection.id);
        const lecture = lecturesByCreatedAt[lectureNum - 1];
        if (!lecture) {
          setPanelData(null);
          setPanelLectureId(null);
          return;
        }
        setPanelLectureId(lecture.id);
        setPanelData({
          courseTitle: course?.course_title ?? '',
          lectureNum,
          topicNum: null,
          title: lectureDisplayTitle(lecture),
          summary: lecture.summary ? stripSidCitations(lecture.summary) : null,
          clusterName: null,
          relatedTopics: [],
        });
        return;
      }

      // Topic View: ゴーストノードには詳細シートを出さない(Flutter版と同じ)。
      const node = map.nodes.find((n) => n.topic_id === selection.id);
      if (!node) {
        setPanelData(null);
        setPanelLectureId(null);
        return;
      }
      const lecture = lecturesByCreatedAt.find((l) => l.id === node.source_lecture_id);
      if (!lecture) {
        setPanelData(null);
        setPanelLectureId(null);
        return;
      }

      const clusterName = node.cluster_id ? map.clusters.find((c) => c.cluster_id === node.cluster_id)?.name ?? null : null;
      const relatedTopics: RelatedTopicEdge[] = [];
      for (const edge of map.edges) {
        const relationType = edge.relation_type.replace(/_/g, ' ');
        if (edge.source_id === node.topic_id) {
          const target = map.nodes.find((n) => n.topic_id === edge.target_id);
          if (target) relatedTopics.push({ title: target.title, relationType, isOutgoing: true });
        } else if (edge.target_id === node.topic_id) {
          const source = map.nodes.find((n) => n.topic_id === edge.source_id);
          if (source) relatedTopics.push({ title: source.title, relationType, isOutgoing: false });
        }
      }

      let summary: string | null = null;
      try {
        const topics = await listLectureTopics(lecture.id);
        const match = topics.find(
          (t) => t.index === node.topic_index_in_lecture || t.topic_title === node.title
        );
        summary = match?.summary ? stripSidCitations(match.summary) : null;
      } catch {
        summary = null;
      }
      if (cancelled) return;

      setPanelLectureId(lecture.id);
      setPanelData({
        courseTitle: course?.course_title ?? '',
        lectureNum: lectureNumBySourceLectureId.get(node.source_lecture_id) ?? 0,
        topicNum: node.topic_index_in_lecture,
        title: node.title,
        summary,
        clusterName,
        relatedTopics,
      });
    }

    resolve();
    return () => {
      cancelled = true;
    };
  }, [map, selection, lecturesByCreatedAt, lectureNumBySourceLectureId, course]);

  const handleSelectNode = useCallback((nodeId: string) => {
    setSelection((prev) => (prev?.type === 'node' && prev.id === nodeId ? null : { type: 'node', id: nodeId }));
  }, []);

  const handleSelectCluster = useCallback((clusterId: string) => {
    setSelection((prev) => (prev?.type === 'cluster' && prev.id === clusterId ? null : { type: 'cluster', id: clusterId }));
  }, []);

  const handleClearSelection = useCallback(() => setSelection(null), []);

  const handleSelectLecture = useCallback(
    (lectureNum: number) => {
      setSelection((prev) => {
        const same = prev?.type === 'lecture' && prev.id === String(lectureNum);
        if (same) return null;
        return { type: 'lecture', id: String(lectureNum) };
      });
      if (!(selection?.type === 'lecture' && selection.id === String(lectureNum))) {
        canvasRef.current?.focusLecture(lectureNum);
      }
    },
    [selection]
  );

  const handleCloseSheet = useCallback(() => {
    // シートを閉じるだけ -- Lecture/Topic Viewの選択(ハイライト)自体は保持する。
    setPanelData(null);
    setPanelLectureId(null);
  }, []);

  const handleGoToLecture = useCallback(() => {
    if (!panelLectureId) return;
    setSelection(null);
    setPanelData(null);
    navigate(`/lectures/${panelLectureId}`);
  }, [panelLectureId, navigate]);

  if (loading) return <TopicMapSkeleton />;
  if (error) return <PageState kind="error" message={error} />;
  if (!map || !layout || map.nodes.length === 0) {
    return (
      <PageState
        kind="empty"
        title="No topic map yet"
        message="The topic map is built once lectures in this course finish processing."
        action={<Link to={`/courses/${courseId}`}>Back to course</Link>}
      />
    );
  }

  const viewMode = selection
    ? selection.type === 'lecture'
      ? 'lecture'
      : selection.type === 'node'
      ? 'topic'
      : 'cluster'
    : 'cluster';

  const modeTitle =
    viewMode === 'lecture'
      ? t('topicMapModeLecture')
      : viewMode === 'topic'
      ? t('topicMapModeTopic')
      : t('topicMapModeCluster');

  const courseTitle = course?.course_title || (isJa ? 'コース' : 'Course');

  return (
    <div className="tm-page">
      <header className="tm-header">
        <div className="tm-header-bar">
          <div className="tm-header-left">
            <Link
              to={`/courses/${courseId}`}
              className="tm-back-btn"
              title={courseTitle}
              aria-label={isJa ? `${courseTitle}へ戻る` : `Back to ${courseTitle}`}
            >
              ← <span className="tm-back-btn-text">{courseTitle}</span>
            </Link>
          </div>

          <div className="tm-header-center">
            <h1 className="tm-mode-title">{modeTitle}</h1>
            {selectedEntityLabel && <p className="tm-mode-subtitle">{selectedEntityLabel}</p>}
          </div>

          <div className="tm-header-right">
            <div className="tm-app-bar-actions">
              {isStale && (
                <button type="button" className="tm-rebuild-btn" onClick={rebuild} disabled={rebuilding}>
                  <RefreshCw size={14} className={rebuilding ? 'animate-spin' : ''} />
                  <span className="tm-rebuild-label">{rebuilding ? (isJa ? '再構築中…' : 'Rebuilding…') : isJa ? 'マップを再構築' : 'Rebuild map'}</span>
                </button>
              )}
              <button type="button" className="tm-zoom-btn" onClick={() => canvasRef.current?.zoomBy(1.15)} aria-label="Zoom in">
                <ZoomIn size={18} />
              </button>
              <button type="button" className="tm-zoom-btn" onClick={() => canvasRef.current?.zoomBy(1 / 1.15)} aria-label="Zoom out">
                <ZoomOut size={18} />
              </button>
            </div>
          </div>
        </div>

        {lecturesByCreatedAt.length > 0 && (
          <div className="tm-header-chips">
            <div className="tm-lecture-chips">
              {Array.from({ length: lecturesByCreatedAt.length }, (_, i) => i + 1).map((lectureNum) => (
                <button
                  key={lectureNum}
                  type="button"
                  className={`tm-lecture-chip ${selection?.type === 'lecture' && Number(selection.id) === lectureNum ? 'is-selected' : ''}`}
                  onClick={() => handleSelectLecture(lectureNum)}
                >
                  {t('topicMapLectureChip', { num: String(lectureNum) })}
                </button>
              ))}
            </div>
          </div>
        )}
      </header>

      <div className="tm-canvas-shell">
        <TopicMapCanvas
          ref={canvasRef}
          data={map}
          simulation={layout.simulation}
          canvasSize={layout.canvasSize}
          clusterIdByNodeId={layout.clusterIdByNodeId}
          lectureNumByNodeId={layout.lectureNumByNodeId}
          selection={selection}
          onSelectNode={handleSelectNode}
          onSelectCluster={handleSelectCluster}
          onClearSelection={handleClearSelection}
        />

        {isStale && <p className="notice tm-stale-notice">{isJa ? 'このマップは最新でない可能性があります。' : 'This map may be out of date — lectures changed since it was last built.'}</p>}

        <TopicMapDetailSheet data={panelData} onClose={handleCloseSheet} onGoToLecture={handleGoToLecture} />
      </div>
    </div>
  );
};
