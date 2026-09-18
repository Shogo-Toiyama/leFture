import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { RefreshCw, X } from 'lucide-react';
import { useTranscript } from '../../hooks/useTranscript';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useAudioArtifact } from '../../hooks/useAudioArtifact';
import { useAudioPlayer } from '../../hooks/useAudioPlayer';
import { useLanguage } from '../../i18n/LanguageContext';
import { getLecture } from '../../lib/lectures';
import { stripSidCitations } from '../../lib/sidCitation';
import { topicColor } from '../../lib/topicColors';
import type { LectureTopic, TranscriptSentence } from '../../types/content';
import type { Lecture } from '../../types/lecture';
import { AudioPlayerBar, formatDuration, type TopicRange } from './AudioPlayerBar';
import { TranscriptViewSkeleton } from './TranscriptViewSkeleton';

/** "s123" のようなSIDから連番部分を取り出す。 */
function sidToInt(sid: string | null | undefined): number | null {
  if (!sid) return null;
  const match = /[sS](\d+)/.exec(sid);
  return match ? Number(match[1]) : null;
}

type Row =
  | { kind: 'topic'; topic: LectureTopic; topicIndex: number }
  | { kind: 'sentence'; sentence: TranscriptSentence; sentenceIndex: number };

interface TranscriptViewProps {
  lectureId: string;
  /** 出典リンクから渡される強調対象のSID。 */
  highlightSids: Set<string>;
  onClose: () => void;
  /** 'page' は全画面、'sheet' は本文の横に並ぶパネル。 */
  variant: 'page' | 'sheet';
}

/**
 * 文字起こし＆音声の中身。transcript_page.dart 準拠。
 * 全画面ページと、出典表示用の横並びシートの両方で使う。
 * 配色はコースカラーではなく leFture のゴールドで固定する。
 */
export const TranscriptView: React.FC<TranscriptViewProps> = ({
  lectureId,
  highlightSids,
  onClose,
  variant,
}) => {
  const { t } = useLanguage();
  const { sentences, loading, error } = useTranscript(lectureId);
  const { topics } = useLectureTopics(lectureId);
  const [lecture, setLecture] = useState<Lecture | null>(null);

  const audio = useAudioArtifact(lecture?.audio_path);
  const player = useAudioPlayer(audio.url);

  const activeRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const idleTimer = useRef<number | null>(null);
  const suppressAutoScroll = useRef(false);
  const didJumpToHighlight = useRef(false);
  const pendingSeek = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    getLecture(lectureId)
      .then((data) => {
        if (!cancelled) setLecture(data);
      })
      .catch(() => {
        /* 音声が引けないだけなので、本文の表示は続ける */
      });
    return () => {
      cancelled = true;
    };
  }, [lectureId]);

  const lines = useMemo(() => sentences ?? [], [sentences]);

  /** 各トピックの開始文のインデックス。見出しタイルの差し込み位置。 */
  const topicStartAt = useMemo(() => {
    const map = new Map<number, { topic: LectureTopic; topicIndex: number }>();
    topics.forEach((topic, topicIndex) => {
      const startNum = sidToInt(topic.start_sid);
      if (startNum === null) return;
      const at = lines.findIndex((s) => {
        const n = sidToInt(s.sid);
        return n !== null && n >= startNum;
      });
      if (at >= 0 && !map.has(at)) map.set(at, { topic, topicIndex });
    });
    return map;
  }, [topics, lines]);

  const rows = useMemo(() => {
    const list: Row[] = [];
    lines.forEach((sentence, sentenceIndex) => {
      const header = topicStartAt.get(sentenceIndex);
      if (header) list.push({ kind: 'topic', ...header });
      list.push({ kind: 'sentence', sentence, sentenceIndex });
    });
    return list;
  }, [lines, topicStartAt]);

  /** 各トピックの開始秒。目次ジャンプと前後送りで使う。 */
  const topicStartSeconds = useMemo(
    () =>
      topics.map((topic) => {
        const startNum = sidToInt(topic.start_sid);
        if (startNum === null) return null;
        const hit = lines.find((s) => {
          const n = sidToInt(s.sid);
          return n !== null && n >= startNum;
        });
        return hit ? hit.start : null;
      }),
    [topics, lines]
  );

  const topicRanges = useMemo<TopicRange[]>(() => {
    if (player.duration <= 0) return [];
    return topics.map((_, i) => {
      const start = topicStartSeconds[i];
      const nextStart = topicStartSeconds.slice(i + 1).find((v) => v !== null) ?? null;
      if (start === null) return { start: 0, end: 0 };
      return { start: start / player.duration, end: (nextStart ?? player.duration) / player.duration };
    });
  }, [topics, topicStartSeconds, player.duration]);

  const activeSentenceIndex = useMemo(() => {
    let idx = -1;
    for (let i = 0; i < lines.length; i += 1) {
      if (player.position >= lines[i].start) idx = i;
      else break;
    }
    return idx;
  }, [lines, player.position]);

  const currentTopicIndex = useMemo(() => {
    let idx = -1;
    topicStartSeconds.forEach((start, i) => {
      if (start !== null && player.position >= start) idx = i;
    });
    return idx;
  }, [topicStartSeconds, player.position]);

  const jumpToTopic = useCallback(
    (topic: LectureTopic) => {
      const i = topics.findIndex((candidate) => candidate.id === topic.id);
      const start = i >= 0 ? topicStartSeconds[i] : null;
      if (start !== null && start !== undefined) player.seek(start);
      document.getElementById(`topic-${topic.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    },
    [topics, topicStartSeconds, player]
  );

  const stepTopic = useCallback(
    (delta: 1 | -1) => {
      if (topics.length === 0) return;
      // 「戻る」はトピック開始から3秒以上経っていれば頭出し、それ以前なら前のトピックへ。
      const startOfCurrent = currentTopicIndex >= 0 ? topicStartSeconds[currentTopicIndex] : null;
      if (delta === -1 && startOfCurrent !== null && startOfCurrent !== undefined && player.position - startOfCurrent >= 3) {
        jumpToTopic(topics[currentTopicIndex]);
        return;
      }
      const target = Math.min(Math.max(currentTopicIndex + delta, 0), topics.length - 1);
      jumpToTopic(topics[target]);
    },
    [topics, currentTopicIndex, topicStartSeconds, player.position, jumpToTopic]
  );

  // 再生中は現在行を画面内に保つ。ユーザーが操作したら5秒だけ止める。
  useEffect(() => {
    if (!autoScroll || suppressAutoScroll.current) return;
    activeRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [activeSentenceIndex, autoScroll]);

  const noteInteraction = useCallback(() => {
    if (!autoScroll) return;
    suppressAutoScroll.current = true;
    if (idleTimer.current) window.clearTimeout(idleTimer.current);
    idleTimer.current = window.setTimeout(() => {
      suppressAutoScroll.current = false;
    }, 5000);
  }, [autoScroll]);

  useEffect(
    () => () => {
      if (idleTimer.current) window.clearTimeout(idleTimer.current);
    },
    []
  );

  // 強調対象が指定されたら、その行まで送って音声も頭出しする。
  const highlightKey = useMemo(() => [...highlightSids].sort().join(','), [highlightSids]);
  useEffect(() => {
    didJumpToHighlight.current = false;
  }, [highlightKey]);

  useEffect(() => {
    if (didJumpToHighlight.current || highlightSids.size === 0 || lines.length === 0) return;
    const hit = lines.find((s) => highlightSids.has(s.sid));
    if (!hit) return;
    didJumpToHighlight.current = true;
    suppressAutoScroll.current = true;
    pendingSeek.current = hit.start;
    const timer = window.setTimeout(() => {
      document.getElementById(`sid-${hit.sid}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 0);
    return () => window.clearTimeout(timer);
  }, [highlightSids, lines, highlightKey]);

  // 音声のメタデータが揃ってから頭出しする(揃う前のseekは無視されるため)。
  useEffect(() => {
    if (!player.ready || pendingSeek.current === null) return;
    player.seek(pendingSeek.current);
    pendingSeek.current = null;
  }, [player.ready, player]);

  const hasAudio = Boolean(lecture?.audio_path);

  return (
    <>
      <header className="pv-top">
        <div className="pv-top-row">
          <button type="button" className="pv-icon-btn" onClick={onClose} aria-label={t('close')}>
            <X size={20} />
          </button>
          <span className="pv-title">{t('transcript')}</span>
          {hasAudio ? (
            <button
              type="button"
              className={`pv-icon-btn ${autoScroll ? 'is-active' : ''}`}
              onClick={() => {
                suppressAutoScroll.current = false;
                setAutoScroll((v) => !v);
              }}
              aria-pressed={autoScroll}
              aria-label={autoScroll ? t('transcriptAutoScrollOn') : t('transcriptAutoScrollOff')}
              title={autoScroll ? t('transcriptAutoScrollOn') : t('transcriptAutoScrollOff')}
            >
              <RefreshCw size={18} />
            </button>
          ) : (
            <span style={{ width: 36 }} />
          )}
        </div>
      </header>

      <div className="tsv-scroll" onWheel={noteInteraction} onPointerDown={noteInteraction}>
        <div className={`tsv-sheet ${variant === 'sheet' ? 'is-narrow' : ''}`}>
          {loading && <TranscriptViewSkeleton />}
          {!loading && error && <p className="tsv-status">{error}</p>}
          {!loading && !error && rows.length === 0 && <p className="tsv-status">{t('transcriptEmpty')}</p>}

          {rows.map((row) => {
            if (row.kind === 'topic') {
              return (
                <div
                  key={`topic-${row.topic.id}`}
                  id={`topic-${row.topic.id}`}
                  className="tsv-topic-head"
                  style={{ ['--seg' as string]: topicColor(row.topicIndex, topics.length) }}
                >
                  <span className="tsv-topic-bar" />
                  <span className="tsv-topic-label">{t('topicLabel', { index: String(row.topic.index) })}</span>
                  <span className="tsv-topic-title">{row.topic.topic_title}</span>
                </div>
              );
            }

            const { sentence, sentenceIndex } = row;
            const isActive = sentenceIndex === activeSentenceIndex && player.ready;
            const isCited = highlightSids.has(sentence.sid);
            const isAside = (sentence.role ?? 'CONTENT').toUpperCase() === 'OFF_TOPIC';

            return (
              <div
                key={sentence.sid}
                id={`sid-${sentence.sid}`}
                ref={isActive ? activeRef : undefined}
                className={[
                  'tsv-line',
                  isActive ? 'is-active' : '',
                  isCited ? 'is-cited' : '',
                  isAside ? 'is-aside' : '',
                  player.ready ? 'is-seekable' : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                onClick={() => player.ready && player.seek(sentence.start)}
              >
                <span className="tsv-time">{formatDuration(sentence.start)}</span>
                <span className="tsv-text">{stripSidCitations(sentence.text)}</span>
              </div>
            );
          })}
        </div>
      </div>

      {hasAudio && (
        <>
          <audio ref={player.ref} src={audio.url ?? undefined} preload="metadata" />
          <AudioPlayerBar
            position={player.position}
            duration={player.duration}
            playing={player.playing}
            rate={player.rate}
            ready={player.ready}
            loading={audio.loading}
            errorMessage={audio.error}
            topics={topics}
            topicRanges={topicRanges}
            currentTopicIndex={currentTopicIndex}
            compact={variant === 'sheet'}
            labels={{
              topicIndex: t('transcriptTopicIndex'),
              downloading: t('transcriptDownloadingAudio'),
              preparing: t('transcriptPreparingAudio'),
              loadError: t('transcriptAudioError'),
              previousTopic: t('transcriptPreviousTopic'),
              nextTopic: t('transcriptNextTopic'),
              rewind: t('transcriptRewind'),
              forward: t('transcriptForward'),
              play: t('transcriptPlay'),
              pause: t('transcriptPause'),
              speed: t('transcriptSpeed'),
            }}
            onSeek={player.seek}
            onToggle={player.toggle}
            onSkip={player.skip}
            onRateChange={player.setRate}
            onTopicSelected={jumpToTopic}
            onPreviousTopic={() => stepTopic(-1)}
            onNextTopic={() => stepTopic(1)}
          />
        </>
      )}
    </>
  );
};
