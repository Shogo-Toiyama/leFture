import { useState } from 'react';

const empty = [];
const row = (id, role, content, status = 'complete') => ({
  id, role, content, status, citations: [], context: {}, created_at: '2026-11-20T00:00:00Z',
});
const answerText = 'An answer with several lines. '.repeat(15);

export function useChatConversation() {
  const [messages, setMessages] = useState(() =>
    Array.from({ length: 18 }, (_, i) => i % 2 === 0
      ? row(`question-${i}`, 'user', `Question ${i}`)
      : row(`answer-${i}`, 'assistant', answerText,
        i === 17 && window.initialGenerating ? 'streaming' : 'complete')));

  window.finishGeneration = () => setMessages((prev) => [
    ...prev.slice(0, -1),
    {
      ...prev.at(-1),
      status: 'complete',
      citations: [{
        n: 'W1', source_type: 'web', label: 'Example source', url: 'https://example.com/',
      }],
    },
  ]);
  window.appendText = () => setMessages((prev) => [
    ...prev.slice(0, -1), { ...prev.at(-1), content: prev.at(-1).content + '\n\n' + answerText },
  ]);
  return {
    messages, attachments: empty, loading: false, sending: false, hasMore: false,
    send: (content) => setMessages((prev) => [
      ...prev, row('sent-message', 'user', content),
      row('new-answer', 'assistant', answerText, 'streaming'),
    ]),
  };
}
