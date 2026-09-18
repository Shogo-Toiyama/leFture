import React, { useRef, useState } from 'react';
import {
  ChevronDown,
  ChevronUp,
  ListOrdered,
  Pause,
  Play,
  RotateCcw,
  RotateCw,
  SkipBack,
  SkipForward,
} from 'lucide-react';
import { topicColor } from '../../lib/topicColors';
import type { LectureTopic } from '../../types/content';

export interface TopicRange {
  /** 0..1 */
  start: number;
  /** 0..1 */
  end: number;
}

const SPEEDS = [0.75, 1, 1.25, 1.5, 1.75, 2];

export function formatDuration(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

interface AudioPlayerBarProps {
  position: number;
  duration: number;
  playing: boolean;
  rate: number;
  ready: boolean;
  loading: boolean;
  errorMessage: string | null;
  topics: LectureTopic[];
  /** topics と同じ並びの再生位置レンジ。長さが違う場合は無色の一本バーになる。 */
  topicRanges: TopicRange[];
  currentTopicIndex: number;
  /** 横並びシートなど幅の狭い場所で使うときは余白を詰める。 */
  compact?: boolean;
  labels: {
    topicIndex: string;
    downloading: string;
    preparing: string;
    loadError: string;
    previousTopic: string;
    nextTopic: string;
    rewind: string;
    forward: string;
    play: string;
    pause: string;
    speed: string;
  };
  onSeek: (seconds: number) => void;
  onToggle: () => void;
  onSkip: (delta: number) => void;
  onRateChange: (rate: number) => void;
  onTopicSelected: (topic: LectureTopic) => void;
  onPreviousTopic: () => void;
  onNextTopic: () => void;
}

/**
 * audio_player_bar.dart 相当の再生バー。
 * トピックごとに区切られたシークバー、上に開くトピック目次、
 * 左右対称のコントロールという構成をそのまま踏襲する。
 */
export const AudioPlayerBar: React.FC<AudioPlayerBarProps> = ({
  position,
  duration,
  playing,
  rate,
  ready,
  loading,
  errorMessage,
  topics,
  topicRanges,
  currentTopicIndex,
  compact = false,
  labels,
  onSeek,
  onToggle,
  onSkip,
  onRateChange,
  onTopicSelected,
  onPreviousTopic,
  onNextTopic,
}) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const [speedOpen, setSpeedOpen] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);
  const scrubbing = useRef(false);

  const percent = duration > 0 ? Math.min(Math.max(position / duration, 0), 1) : 0;
  const hasTopics = topics.length > 0;
  const currentTopic = currentTopicIndex >= 0 ? topics[currentTopicIndex] : undefined;

  const seekFromPointer = (clientX: number) => {
    const box = trackRef.current?.getBoundingClientRect();
    if (!box || box.width === 0 || duration <= 0) return;
    const ratio = Math.min(Math.max((clientX - box.left) / box.width, 0), 1);
    onSeek(ratio * duration);
  };

  const handlePointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!ready) return;
    scrubbing.current = true;
    event.currentTarget.setPointerCapture(event.pointerId);
    seekFromPointer(event.clientX);
  };

  const handlePointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!scrubbing.current) return;
    seekFromPointer(event.clientX);
  };

  const endScrub = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!scrubbing.current) return;
    scrubbing.current = false;
    event.currentTarget.releasePointerCapture(event.pointerId);
  };

  // トピックのレンジが揃っていないうちは、色分けのない一本のバーとして描く。
  const segments =
    topicRanges.length === topics.length && topicRanges.length > 0
      ? buildSegments(topicRanges, topics.length)
      : [{ start: 0, end: 1, color: null }];

  return (
    <div className={`tsv-player ${compact ? 'is-compact' : ''}`}>
      {hasTopics && menuOpen && (
        <div className="tsv-topic-menu">
          <div className="tsv-topic-menu-head">
            <span className="tsv-inner">
              <ListOrdered size={15} />
              {labels.topicIndex}
            </span>
          </div>
          <div className="tsv-topic-menu-list">
            {topics.map((topic, i) => (
              <button
                key={topic.id}
                type="button"
                className={`tsv-topic-menu-item ${i === currentTopicIndex ? 'is-current' : ''}`}
                style={{ ['--seg' as string]: topicColor(i, topics.length) }}
                onClick={() => {
                  onTopicSelected(topic);
                  setMenuOpen(false);
                }}
              >
                <span className="tsv-topic-chip">{i + 1}</span>
                <span className="tsv-topic-menu-title">{topic.topic_title}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {hasTopics && currentTopic && (
        <button
          type="button"
          className="tsv-topic-current"
          style={{ ['--seg' as string]: topicColor(currentTopicIndex, topics.length) }}
          onClick={() => setMenuOpen((v) => !v)}
        >
          <span className="tsv-inner">
            <span className="tsv-topic-chip is-solid">{currentTopicIndex + 1}</span>
            <span className="tsv-topic-current-title">{currentTopic.topic_title}</span>
            {menuOpen ? <ChevronDown size={17} /> : <ChevronUp size={17} />}
          </span>
        </button>
      )}

      <div className="tsv-player-main">
        {loading ? (
          <p className="tsv-player-status">{labels.downloading}</p>
        ) : errorMessage ? (
          <p className="tsv-player-status">{`${labels.loadError} ${errorMessage}`}</p>
        ) : !ready ? (
          <p className="tsv-player-status">{labels.preparing}</p>
        ) : (
          <>
            <div
              className="tsv-bar"
              ref={trackRef}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={endScrub}
              onPointerCancel={endScrub}
              role="slider"
              aria-label="Seek"
              aria-valuemin={0}
              aria-valuemax={Math.round(duration)}
              aria-valuenow={Math.round(position)}
              tabIndex={0}
              onKeyDown={(event) => {
                if (event.key === 'ArrowRight') onSkip(5);
                if (event.key === 'ArrowLeft') onSkip(-5);
              }}
            >
              {segments.map((segment, i) => {
                const width = segment.end - segment.start;
                const fill = Math.min(Math.max((percent - segment.start) / (width || 1), 0), 1);
                return (
                  <span
                    key={i}
                    className="tsv-seg"
                    style={{
                      left: `${segment.start * 100}%`,
                      width: `calc(${width * 100}% - 4px)`,
                      ['--seg' as string]: segment.color ?? 'var(--pv-accent)',
                    }}
                  >
                    <span className="tsv-seg-fill" style={{ width: `${fill * 100}%` }} />
                  </span>
                );
              })}
              <span className="tsv-knob" style={{ left: `${percent * 100}%` }} />
            </div>

            <div className="tsv-times">
              <span>{formatDuration(position)}</span>
              <span>{formatDuration(duration)}</span>
            </div>

            <div className="tsv-controls">
              <div className="tsv-speed">
                <button
                  type="button"
                  className={`tsv-speed-btn ${speedOpen ? 'is-active' : ''}`}
                  onClick={() => setSpeedOpen((v) => !v)}
                  aria-label={labels.speed}
                >
                  {rate}x
                </button>
                {speedOpen && (
                  <div className="tsv-speed-menu">
                    {SPEEDS.map((speed) => (
                      <button
                        key={speed}
                        type="button"
                        className={speed === rate ? 'is-current' : ''}
                        onClick={() => {
                          onRateChange(speed);
                          setSpeedOpen(false);
                        }}
                      >
                        {speed}x
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <button
                type="button"
                className="tsv-ctrl"
                onClick={onPreviousTopic}
                disabled={!hasTopics}
                aria-label={labels.previousTopic}
                title={labels.previousTopic}
              >
                <SkipBack size={21} />
              </button>
              <button
                type="button"
                className="tsv-ctrl"
                onClick={() => onSkip(-10)}
                aria-label={labels.rewind}
                title={labels.rewind}
              >
                <RotateCcw size={20} />
              </button>

              <button
                type="button"
                className="tsv-play"
                onClick={onToggle}
                aria-label={playing ? labels.pause : labels.play}
              >
                {playing ? <Pause size={24} fill="currentColor" /> : <Play size={24} fill="currentColor" />}
              </button>

              <button
                type="button"
                className="tsv-ctrl"
                onClick={() => onSkip(10)}
                aria-label={labels.forward}
                title={labels.forward}
              >
                <RotateCw size={20} />
              </button>
              <button
                type="button"
                className="tsv-ctrl"
                onClick={onNextTopic}
                disabled={!hasTopics}
                aria-label={labels.nextTopic}
                title={labels.nextTopic}
              >
                <SkipForward size={21} />
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

interface Segment {
  start: number;
  end: number;
  color: string | null;
}

/** トピックのレンジの隙間を無色のセグメントで埋め、バー全体を覆う。 */
function buildSegments(ranges: TopicRange[], total: number): Segment[] {
  const segments: Segment[] = [];
  let cursor = 0;
  ranges.forEach((range, i) => {
    const start = Math.min(Math.max(range.start, 0), 1);
    const end = Math.min(Math.max(range.end, 0), 1);
    if (start > cursor + 0.001) segments.push({ start: cursor, end: start, color: null });
    if (end > start) {
      segments.push({ start, end, color: topicColor(i, total) });
      cursor = end;
    }
  });
  if (cursor < 0.999) segments.push({ start: cursor, end: 1, color: null });
  return segments;
}
