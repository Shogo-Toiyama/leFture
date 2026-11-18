import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const folder = new URL('./', import.meta.url);
const webapp = new URL('../../../webapp/', folder);
const resolveDir = fileURLToPath(webapp);
const require = createRequire(new URL('package.json', webapp));
const { build } = require('esbuild');

const fixtures = {
  LanguageContext: `
    import { en } from './src/i18n/locales/en';
    export const useLanguage = () => ({ t: (key) => en[key] ?? key });
  `,
  useChatConversation: `
    import { useState } from 'react';
    const empty = [];
    const row = (id) => ({ id, role: 'user', content: id, status: 'complete', context: {} });
    export function useChatConversation() {
      const [messages, setMessages] = useState(() =>
        Array.from({ length: 16 }, (_, i) => i === 15 && window.initialGenerating
          ? { ...row('message-' + i), role: 'assistant', status: 'streaming' }
          : row('message-' + i)));
      window.finishGeneration = () => setMessages((prev) => [
        ...prev.slice(0, -1), { ...prev.at(-1), status: 'complete' },
      ]);
      window.appendDelta = () => setMessages((prev) => {
        const message = prev.at(-1);
        return [...prev.slice(0, -1), {
          ...message,
          height: (message.height ?? 90) + 120,
          content: message.content + ' new text',
        }];
      });
      return {
        messages, attachments: empty, loading: false, sending: false, hasMore: false,
        send: () => setMessages((prev) => [
          ...prev, row('sent-message'),
          { ...row('new-answer'), role: 'assistant', status: 'streaming' },
        ]),
      };
    }
  `,
  ChatComposer: `
    import React from 'react';
    export const ChatComposer = ({ onSend }) =>
      <button id="probe-send" onClick={() => onSend('Question')}>Send</button>;
  `,
  ChatMessageItem: `
    import React from 'react';
    export const ChatMessageItem = ({ message }) =>
      <article className="probe-message" style={{ flexBasis: message.height }}>
        {message.content}
      </article>;
  `,
  AttachmentListModal: 'export const AttachmentListModal = () => null;',
  AttachmentViewerModal: 'export const AttachmentViewerModal = () => null; export const viewableFromAttachment = () => null;',
  LaunchGateBackdrop: 'export const LaunchGateBackdrop = () => null;',
};

const browser = process.env.CHROME_BIN ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const tmp = await mkdtemp(join(tmpdir(), 'web-chat-scroll-'));
try {
  await build({
    absWorkingDir: resolveDir,
    stdin: {
      contents: await readFile(new URL('fixture.jsx', folder), 'utf8'),
      loader: 'jsx',
      resolveDir,
    },
    bundle: true,
    outfile: join(tmp, 'fixture.js'),
    plugins: [{
      name: 'chat-test-fixtures',
      setup(builder) {
        builder.onResolve(
          { filter: /\/(LanguageContext|useChatConversation|ChatComposer|ChatMessageItem|AttachmentListModal|AttachmentViewerModal|LaunchGateBackdrop)$/ },
          ({ path }) => ({ path: path.split('/').at(-1), namespace: 'fixture' }),
        );
        builder.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
          contents: fixtures[path], resolveDir, loader: 'jsx',
        }));
      },
    }],
  });
  const styles = await readFile(new URL('src/index.css', webapp), 'utf8');
  const html = join(tmp, 'index.html');
  await writeFile(html, `<!doctype html><html lang="en"><meta charset="utf-8">
    <style>${styles}
      #root { display: flex; flex-direction: column; height: 460px; width: 560px; }
      #root .probe-message { flex: 0 0 90px; }
    </style>
    <div id="root"></div><pre id="results"></pre><script src="fixture.js"></script>
  </html>`);
  const result = spawnSync(browser, [
    '--headless', '--disable-background-networking', '--disable-gpu',
    '--no-first-run', '--no-default-browser-check', '--run-all-compositor-stages-before-draw',
    '--virtual-time-budget=8000', '--dump-dom', `--user-data-dir=${join(tmp, 'profile')}`,
    pathToFileURL(html).href,
  ], { encoding: 'utf8', timeout: 20000, maxBuffer: 2 * 1024 * 1024 });
  const report = result.stdout?.match(/<pre id="results">([\s\S]*?)<\/pre>/)?.[1] ?? '';
  const outcome = report.trim() || String(result.error ?? result.stderr);
  console.log(outcome);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const resultsDir = process.env.WEB_CHAT_RESULTS_DIR ?? fileURLToPath(new URL('results/', folder));
  await writeFile(join(resultsDir, `${stamp}.log`), `${outcome}\n`);
  if (result.status !== 0 || !report.includes('ALL PASSED')) process.exitCode = 1;
} finally {
  await rm(tmp, { recursive: true });
}
