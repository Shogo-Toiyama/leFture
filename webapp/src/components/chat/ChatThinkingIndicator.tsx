import React, { useEffect, useState } from 'react';
import { ChatWorld } from './LaunchGateBackdrop';
import { ThinkingNebula } from './ThinkingNebula';

interface ChatThinkingIndicatorProps {
  label: string;
  world?: ChatWorld;
  startedAt?: string | number | Date;
  nebulaSize?: number;
}

const CHAT_ELAPSED_VISIBLE_AFTER_SECONDS = 5;

export const ChatThinkingIndicator: React.FC<ChatThinkingIndicatorProps> = ({
  label,
  world = 'universe',
  startedAt,
  nebulaSize = 34,
}) => {
  const [seconds, setSeconds] = useState(0);

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

  const showSeconds = seconds >= CHAT_ELAPSED_VISIBLE_AFTER_SECONDS;

  return (
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
};
