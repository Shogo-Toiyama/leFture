import React, { useEffect, useRef, useState } from 'react';
import { ChatWorld } from './LaunchGateBackdrop';
import { ThinkingNebula } from './ThinkingNebula';

interface ChatThinkingIndicatorProps {
  label: string;
  world?: ChatWorld;
  startedAt?: string | number | Date;
  nebulaSize?: number;
  thoughtText?: string;
}

const CHAT_ELAPSED_VISIBLE_AFTER_SECONDS = 5;

export const ChatThinkingIndicator: React.FC<ChatThinkingIndicatorProps> = ({
  label,
  world = 'universe',
  startedAt,
  nebulaSize = 34,
  thoughtText,
}) => {
  const [seconds, setSeconds] = useState(0);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const startTime = startedAt ? new Date(startedAt).getTime() : Date.now();

    const getElapsed = () =>
      Math.max(0, Math.floor((Date.now() - startTime) / 1000));

    setSeconds(getElapsed());

    const interval = setInterval(() => {
      setSeconds(getElapsed());
    }, 1000);

    return () => clearInterval(interval);
  }, [startedAt]);

  useEffect(() => {
    if (thoughtText && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [thoughtText]);

  const showSeconds = seconds >= CHAT_ELAPSED_VISIBLE_AFTER_SECONDS;
  const hasThought = Boolean(thoughtText && thoughtText.trim().length > 0);

  const indicatorRow = (
    <div
      className="chat-thinking-indicator"
      role="status"
      aria-live="polite"
      aria-label={label}
    >
      <ThinkingNebula world={world} size={nebulaSize} />
      <div className="chat-thinking-text-wrap">
        <span className="chat-thinking-label slabel">{label}</span>
        {showSeconds && (
          <span className="chat-thinking-seconds">{seconds}s</span>
        )}
      </div>
    </div>
  );

  if (!hasThought) {
    return indicatorRow;
  }

  return (
    <div className="chat-thinking-indicator-wrapper">
      {indicatorRow}
      <div
        ref={scrollRef}
        className="chat-thinking-thought-box"
        style={{ marginLeft: `${nebulaSize + 10}px` }}
      >
        {thoughtText!.trim()}
      </div>
    </div>
  );
};
