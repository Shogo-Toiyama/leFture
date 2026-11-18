import React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { MemoryRouter } from 'react-router-dom';
import { ChatConversation } from './src/components/chat/ChatConversation';

const root = createRoot(document.getElementById('root'));
const results = document.getElementById('results');
let renderId = 0;
const delay = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));
const distance = (list) => list.scrollHeight - list.clientHeight - list.scrollTop;
const check = (condition, detail) => {
  if (!condition) throw new Error(detail);
};

async function open(variant = 'page', generating = true) {
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
  return document.querySelector('.chat-scroll');
}

function wheel(list, dy) {
  list.dispatchEvent(new WheelEvent('wheel', { deltaY: dy, bubbles: true }));
}

function scroll(list, to) {
  list.scrollTop = to;
  list.dispatchEvent(new Event('scroll'));
}

function stream() {
  flushSync(() => window.appendDelta());
}

async function test(name, run) {
  try {
    await run();
    results.textContent += `PASS ${name}\n`;
    return true;
  } catch (error) {
    results.textContent += `FAIL ${name}: ${error.message}\n`;
    return false;
  }
}

async function run() {
  const verdicts = [];
  verdicts.push(await test('Wheel movement pauses follow inside the bottom zone', async () => {
    const list = await open();
    wheel(list, -35);
    scroll(list, list.scrollTop - 35);
    const position = list.scrollTop;
    stream();
    check(Math.abs(list.scrollTop - position) < 2, 'a new message pulled a reader back down');
  }));

  verdicts.push(await test('Sending while reading history preserves the offset', async () => {
    const list = await open('panel', false);
    check(distance(list) <= 2, 'finished conversation did not open at the latest message');
    wheel(list, -450);
    scroll(list, list.scrollTop - 450);
    const position = list.scrollTop;
    flushSync(() => document.querySelector('#probe-send').click());
    check(document.querySelector('.chat-thread').textContent.includes('sent-message'), 'send did not append');
    check(Math.abs(list.scrollTop - position) < 2, 'send jumped to the bottom');
    stream();
    check(Math.abs(list.scrollTop - position) < 2, 'answer dragged the reader after send');
  }));

  verdicts.push(await test('Down arrow jumps immediately and restarts follow', async () => {
    const list = await open();
    wheel(list, -500);
    scroll(list, list.scrollTop - 500);
    await delay(50);
    const arrow = document.querySelector('button[aria-label="Jump to latest message"]');
    check(arrow, 'down arrow is missing away from the bottom');
    const footer = document.querySelector('.chat-footer');
    check(arrow.getBoundingClientRect().bottom < footer.getBoundingClientRect().top,
      'down arrow overlaps the composer');
    flushSync(() => arrow.click());
    await delay();
    check(distance(list) <= 2, 'arrow did not jump to the bottom');
    check(!document.querySelector('.chat-jump-to-bottom'), 'arrow is still visible at the bottom');
    stream();
    check(distance(list) <= 2, 'new messages are not followed after the jump');
  }));

  verdicts.push(await test('Scroll toward the bottom resumes in the near-bottom zone', async () => {
    const list = await open();
    wheel(list, -500);
    scroll(list, list.scrollTop - 500);
    wheel(list, 410);
    await delay(150);
    scroll(list, list.scrollHeight - list.clientHeight - 70);
    stream();
    check(distance(list) <= 2, 'downward movement did not restore follow');
  }));

  verdicts.push(await test('A held pointer pauses follow until after release', async () => {
    const list = await open('panel');
    const start = list.scrollTop;
    list.dispatchEvent(new PointerEvent('pointerdown', {
      pointerId: 1, pointerType: 'mouse', button: 0, bubbles: true,
    }));
    stream();
    check(Math.abs(list.scrollTop - start) < 2, 'new text moved the list during the pointer hold');
    window.dispatchEvent(new PointerEvent('pointerup', { pointerId: 1, pointerType: 'mouse' }));
    await delay(150);
    scroll(list, list.scrollHeight - list.clientHeight - 60);
    stream();
    check(distance(list) <= 2, 'post-release movement did not restore follow');
  }));

  verdicts.push(await test('The near-bottom window expires after 500 ms', async () => {
    const list = await open();
    wheel(list, -500);
    scroll(list, list.scrollTop - 500);
    wheel(list, 100);
    await delay(550);
    scroll(list, list.scrollHeight - list.clientHeight - 70);
    const position = list.scrollTop;
    stream();
    check(Math.abs(list.scrollTop - position) < 2, 'late near-bottom movement restored follow');
    scroll(list, list.scrollHeight);
    stream();
    check(distance(list) <= 2, 'returning all the way down did not restore follow');
  }));

  verdicts.push(await test('Sending at the bottom continues to follow', async () => {
    const list = await open('panel', false);
    check(distance(list) <= 2, 'finished conversation did not open at the latest message');
    flushSync(() => document.querySelector('#probe-send').click());
    stream();
    check(distance(list) <= 2, 'sending at the bottom lost follow');
  }));

  verdicts.push(await test('Completion cancels near-bottom follow and keeps the jump button', async () => {
    const list = await open();
    wheel(list, -450);
    scroll(list, list.scrollTop - 450);
    wheel(list, 380);
    flushSync(() => window.finishGeneration());
    await delay(150);
    scroll(list, list.scrollHeight - list.clientHeight - 70);
    await delay(50);
    check(distance(list) > 60, 'a pre-completion scroll hint snapped the finished conversation');
    wheel(list, 40);
    scroll(list, list.scrollTop + 40);
    await delay(50);
    check(distance(list) > 20, 'scrolling through finished messages snapped to the bottom');

    const arrow = document.querySelector('.chat-jump-to-bottom');
    check(arrow, 'a finished conversation has no jump button');
    flushSync(() => arrow.click());
    check(distance(list) <= 2, 'the jump button did not work after completion');
    wheel(list, -35);
    scroll(list, list.scrollTop - 35);
    check(distance(list) > 25, 'a small upward scroll snapped after using the jump button');
  }));

  results.textContent += verdicts.every(Boolean) ? 'ALL PASSED' : 'FAILED';
}

run().catch((error) => { results.textContent += error.stack; });
