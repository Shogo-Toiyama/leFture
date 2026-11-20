import React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { AppTopbar } from './src/components/AppTopbar';
import { DeepNotesDetailPage } from './src/pages/lectures/DeepNotesDetailPage';
import { ReviewCardsPage } from './src/pages/lectures/ReviewCardsPage';
import { ja } from './src/i18n/locales/ja';

const rootElement = document.getElementById('root');
const root = createRoot(rootElement);
const results = document.getElementById('results');
const isMobile = window.innerWidth < 650;
if (isMobile) {
  rootElement.style.width = '320px';
  const viewportConstraint = document.createElement('style');
  viewportConstraint.textContent = '#root .pv-root { width: 320px; }';
  document.head.append(viewportConstraint);
}

const shortTitle = 'Lecture 7';
const longTitle = '授業タイトル：文字列とパーサーの設計および実装を理解するための実践演習'.repeat(12);
const topicTitle = 'Tokenization';
window.fixtureTopics = [{ id: 'topic', index: 1, topic_title: topicTitle }];
window.fixtureCards = [{ id: 'card', topic_number: 1, card_type: 'hook', card_content: [], metadata: null }];
window.fixtureNotes = [{ id: 'note', topic_number: 1, note_contents: 'Fixture note.', metadata: null }];

async function render(path, lecture, recording = false) {
  window.fixtureLecture = lecture;
  window.fixtureRecording = { phase: recording ? 'recording' : 'idle', elapsedSeconds: 36001 };
  flushSync(() => root.render(
    <MemoryRouter key={path + recording} initialEntries={[path]}>
      <Routes>
        <Route path="/lectures/:lectureId/review-cards" element={<ReviewCardsPage />} />
        <Route path="/lectures/:lectureId/deep-notes/:topicIndex" element={<DeepNotesDetailPage />} />
        <Route path="/" element={<AppTopbar />} />
      </Routes>
    </MemoryRouter>
  ));
  await new Promise((resolve) => setTimeout(resolve, 30));
}

function expect(condition, message) {
  if (!condition) throw Error(message);
}

function inspectTitle(expected, { truncated = false, recording = false, topic = topicTitle } = {}) {
  const title = document.querySelector('.app-topbar-title');
  expect(title?.textContent === expected, 'Lecture title was missing or incorrect');
  expect(title.title === expected, 'Full title tooltip was missing');
  expect(document.querySelector('.pv-title')?.textContent === topic, 'Viewer header lost its title');
  const bar = title.closest('.app-topbar').getBoundingClientRect();
  const text = title.getBoundingClientRect();
  const logo = document.querySelector('.app-topbar-home').getBoundingClientRect();
  const account = document.querySelector('.app-topbar-account').getBoundingClientRect();
  const chip = document.querySelector('.rec-chip');
  const leftEdge = recording ? chip?.getBoundingClientRect().right : logo.right;
  expect(bar.width === (isMobile ? 320 : window.innerWidth), 'Unexpected layout test width');
  expect(!recording || chip?.textContent === '10:00:01', 'Recording timer was missing');
  expect(text.width > 20 && text.left >= leftEdge && account.left >= text.right, 'Title overlaps header controls');
  expect(Math.abs((bar.left + bar.right - text.left - text.right) / 2) < 1, 'Title is not centered');
  if (truncated) {
    expect(title.scrollWidth > title.clientWidth, 'Fixture title did not overflow');
    expect(getComputedStyle(title).textOverflow === 'ellipsis', 'Long title has no ellipsis');
  }
  return `header ${bar.width}px, title ${Math.round(text.width)}px, overlap 0`;
}

const tests = [
  ['Review Cards uses the explicit lecture title', async () => {
    await render('/lectures/explicit/review-cards', { title: shortTitle, title_generated: 'Generated' });
    return inspectTitle(shortTitle);
  }],
  ['Deep Notes centers a long generated title alongside a recording timer', async () => {
    await render('/lectures/generated/deep-notes/1', { title: ' ', title_generated: longTitle }, true);
    return inspectTitle(longTitle, { truncated: true, recording: true });
  }],
  ['Empty Review Cards keeps the lecture title and localized fallback', async () => {
    window.fixtureCards = [];
    await render('/lectures/untitled/review-cards', { title: null, title_generated: null });
    return inspectTitle(ja.lectureUntitled, { topic: ja.reviewCards });
  }],
  ['The default header keeps its layout', async () => {
    await render('/', null);
    expect(!document.querySelector('.app-topbar-title'), 'Default header got a title');
    expect(getComputedStyle(document.querySelector('.app-topbar')).display === 'flex', 'Default header changed layout');
  }],
];

async function run() {
  let failed = false;
  for (const [label, test] of tests) {
    try {
      const detail = await test();
      results.textContent += `PASS ${label}${detail ? ` (${detail})` : ''}\n`;
    } catch (error) {
      failed = true;
      results.textContent += `FAIL ${label}: ${error.message}\n`;
    }
  }
  if (!failed) results.textContent += 'ALL PASSED';
}

run();
