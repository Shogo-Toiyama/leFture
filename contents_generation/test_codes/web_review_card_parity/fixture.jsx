import React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { ReviewCardsPage } from './src/pages/lectures/ReviewCardsPage';

const content = [
  { type: 'paragraph', text: '**サンク(thunk)**を使う' },
  { type: 'quote', text: '要点は**（メモ）**です' },
  { type: 'list', items: ['**サンク(thunk)**', '**遅延評価（lazy）**も重要'] },
  { type: 'paragraph', text: '**機能(API)**と**保存（save）**を使う' },
  { type: 'callout', text: 'コードは `**（そのまま）**`、数式は $x^2$、\\*\\*（リテラル）\\*\\*。' },
  { type: 'code', language: 'text', code_string: '**raw(code)**', explanation: '**引数(arg)**を確認' },
  ...Array.from({ length: 45 }, (_, index) => ({ type: 'paragraph', text: `Paragraph ${index}` })),
];

window.fixtureTopics = [{ id: 'topic', index: 1, topic_title: 'Topic', image_path: null }];
window.fixtureCards = [
  { id: 'first', topic_number: 1, card_type: 'hook', title: 'First', card_content: content, metadata: {
    annotations: [{
      id: 'annotation', block_idx: 0, start_idx: 0, end_idx: 10,
      annotated_words: 'サンク(thunk)', annotation_type: 'highlight', contents: { type: 'marker', color: '#ffe082' },
    }],
  } },
  { id: 'second', topic_number: 1, card_type: 'core_why', title: 'Second', card_content: content, metadata: null },
];

const root = createRoot(document.getElementById('root'));
const results = document.getElementById('results');
const delay = () => new Promise((resolve) => setTimeout(resolve, 440));
const currentScroll = () => document.querySelector('.rcv-layer.is-entering .rcv-scroll');
const outgoingScroll = () => document.querySelector('.rcv-layer.is-leaving .rcv-scroll');

function swipe(element, dx) {
  for (const [type, x] of [['pointerdown', 200], ['pointerup', 200 + dx]]) {
    element.dispatchEvent(new PointerEvent(type, {
      bubbles: true, pointerId: 1, pointerType: 'touch', clientX: x, clientY: 350,
    }));
  }
}

function check(condition, detail) {
  if (!condition) throw new Error(detail);
}

let failures = 0;
async function test(name, run) {
  try {
    const detail = await run();
    results.textContent += `PASS ${name}${detail ? ` (${detail})` : ''}\n`;
  } catch (error) {
    failures++;
    results.textContent += `FAIL ${name}: ${error.message}\n`;
  }
}

async function run() {
  flushSync(() => root.render(
    <MemoryRouter initialEntries={['/lectures/fixture/review']}>
      <Routes><Route path="/lectures/:lectureId/review" element={<ReviewCardsPage />} /></Routes>
    </MemoryRouter>,
  ));
  flushSync(() => document.querySelectorAll('.rcv-seg')[1].click());
  await delay();

  await test('CJK bold includes parentheses at both edges', () => {
    const expected = ['サンク(thunk)', '（メモ）', 'サンク(thunk)', '遅延評価（lazy）', '機能(API)', '保存（save）', '引数(arg)'];
    const spans = [...currentScroll().querySelectorAll('.rcv-blocks strong')];
    const bold = spans.map((element) => element.textContent);
    check(JSON.stringify(bold) === JSON.stringify(expected), `strong elements were ${JSON.stringify(bold)}`);
    check(spans.every((element) => Number(getComputedStyle(element).fontWeight) >= 600), 'strong text is not visually bold');
  });
  await test('Code, escaped markers and math keep their meaning', () => {
    const callout = currentScroll().querySelector('.rc-block-callout');
    check(callout.querySelector('code').textContent === '**（そのまま）**', 'inline code changed');
    check(callout.textContent.includes('**（リテラル）**'), 'escaped stars changed');
    check(callout.querySelector('.katex'), 'math was not rendered');
    check(currentScroll().querySelector('pre code').textContent === '**raw(code)**', 'code block changed');
  });
  await test('Highlight covers the same text as the bold span', () => {
    const paragraph = currentScroll().querySelector('.rc-block-paragraph');
    const marked = paragraph.querySelector('strong mark');
    check(marked?.textContent === 'サンク(thunk)', `highlight covered ${paragraph.querySelector('mark')?.textContent}`);
    check(paragraph.textContent === 'サンク(thunk)を使う', 'rendered text includes Markdown syntax');
  });
  await test('Touch swipe preserves departing and revisited card offsets', async () => {
    currentScroll().scrollTop = 230;
    const first = currentScroll().scrollTop;
    flushSync(() => swipe(currentScroll(), -110));
    const departingFirst = outgoingScroll()?.scrollTop;
    const initialSecond = currentScroll()?.scrollTop;
    await delay();
    currentScroll().scrollTop = 120;
    flushSync(() => swipe(currentScroll(), 110));
    const departingSecond = outgoingScroll()?.scrollTop;
    const restoredFirst = currentScroll()?.scrollTop;
    await delay();
    flushSync(() => document.querySelectorAll('.rcv-seg')[2].click());
    const restoredSecond = currentScroll()?.scrollTop;
    const trace = `first ${first} → ${departingFirst} → ${restoredFirst}, second ${initialSecond} → ${departingSecond} → ${restoredSecond}`;
    check(first === 230 && departingFirst === first && restoredFirst === first
      && initialSecond === 0 && departingSecond === 120 && restoredSecond === 120, trace);
    return trace;
  });
  if (!failures) results.textContent += 'ALL PASSED';
}

run().catch((error) => { results.textContent += `ERROR ${error.stack}`; });
