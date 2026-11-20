import React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { MemoryRouter } from 'react-router-dom';
import { ChatConversation } from './src/components/chat/ChatConversation';

const root = createRoot(document.getElementById('root'));
const results = document.getElementById('results');
const distance = (list) => list.scrollHeight - list.clientHeight - list.scrollTop;
const delay = () => new Promise((resolve) => setTimeout(resolve, 50));
let renderId = 0;
let failures = 0;

function check(condition, detail) {
  if (!condition) throw new Error(detail);
}

function scrollAway(list, pixels) {
  list.dispatchEvent(new WheelEvent('wheel', { deltaY: -pixels, bubbles: true }));
  list.scrollTop -= pixels;
  list.dispatchEvent(new Event('scroll'));
}

async function test(name, generating, run, variant = 'page') {
  try {
    window.initialGenerating = generating;
    flushSync(() => root.render(
      <MemoryRouter>
        <ChatConversation
          key={++renderId}
          threadId="fixture"
          onThreadCreated={() => {}}
          lectureId={null}
          lectureTitle={null}
          selection={null}
          screen={null}
          onOpenCitation={() => {}}
          variant={variant}
        />
      </MemoryRouter>,
    ));
    await delay();
    const list = document.querySelector('.chat-scroll');
    check(distance(list) <= 2, 'conversation did not open at the bottom');
    await run(list);
    results.textContent += `PASS ${name}\n`;
  } catch (error) {
    failures++;
    results.textContent += `FAIL ${name} — ${error.message}\n`;
  }
}

async function run() {
  await test('Completion reveals the citation and action row at the bottom', true, async (list) => {
    flushSync(window.finishGeneration);
    const finalReply = list.querySelector('.chat-msg:last-child');
    const chip = finalReply.querySelector('.chat-cite-chip');
    const actions = finalReply.querySelector('.chat-msg-actions');
    check(chip && actions, 'final controls are missing');
    check(distance(list) <= 2, `completion left ${distance(list)}px below the viewport`);
    check(actions.getBoundingClientRect().bottom <= list.getBoundingClientRect().bottom,
      'the action row is clipped');
    flushSync(window.appendText);
    await delay();
    check(distance(list) > 2, 'layout growth after completion still pulled to the bottom');
  });

  await test('Completion preserves the scroll position of a reader', true, (list) => {
    scrollAway(list, 80);
    const top = list.scrollTop;
    flushSync(window.finishGeneration);
    check(Math.abs(list.scrollTop - top) <= 2, 'completion moved the reader');
  });

  for (const variant of ['page', 'panel']) {
    for (const extraPixels of [0, 1]) {
      const name = extraPixels === 0 ? 'one screen away' : 'one pixel beyond one screen';
      await test(`Sending from ${name} (${variant})`, false, (list) => {
        const expectedDistance = list.clientHeight + extraPixels;
        scrollAway(list, expectedDistance);
        check(distance(list) === expectedDistance, 'the setup failed to reach the test distance');
        const top = list.scrollTop;
        flushSync(() => document.querySelector('#probe-send').click());
        check(list.textContent.includes('A new question'), 'the new question was not rendered');
        for (const stage of ['send', 'delta']) {
          if (stage === 'delta') flushSync(window.appendText);
          if (extraPixels === 0) {
            check(distance(list) <= 2, `${stage} left ${distance(list)}px below the viewport`);
          } else {
            check(Math.abs(list.scrollTop - top) <= 2, `${stage} moved the reader`);
          }
        }
      }, variant);
    }
  }

  results.textContent += failures === 0 ? 'ALL PASSED' : 'FAILED';
}

run();
