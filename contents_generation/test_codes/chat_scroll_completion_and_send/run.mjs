import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const startedAt = performance.now();
const webapp = new URL('../../../webapp/', import.meta.url);
const resolveDir = fileURLToPath(webapp);
const { build } = createRequire(new URL('package.json', webapp))('esbuild');
const fixtures = {
  LanguageContext: `import { en } from './src/i18n/locales/en';
    export const useLanguage = () => ({ t: (key) => en[key] ?? key });`,
  ChatComposer: `import React from 'react';
    export const ChatComposer = ({ onSend }) =>
      <button id="probe-send" onClick={() => onSend('A new question')}>Send</button>;`,
  AttachmentListModal: 'export const AttachmentListModal = () => null;',
  AttachmentViewerModal: `export const AttachmentViewerModal = () => null;
    export const AttachmentKindIcon = () => null;
    export const AttachmentStatusBadge = () => null;
    export const viewableFromAttachment = () => null;`,
  LaunchGateBackdrop: 'export const LaunchGateBackdrop = () => null;',
  ReportSheet: 'export const ReportSheet = () => null;',
  SelectionAskArea: 'export const SelectionAskArea = ({ children }) => children;',
  useAttachmentImageUrl: 'export const useAttachmentImageUrl = () => null;',
  useChatConversation: await readFile(new URL('conversation.js', import.meta.url), 'utf8'),
};
const browser = process.env.CHROME_BIN ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const temp = await mkdtemp(join(tmpdir(), 'chat-scroll-completion-'));
try {
  await build({
    absWorkingDir: resolveDir,
    stdin: {
      contents: await readFile(new URL('fixture.jsx', import.meta.url), 'utf8'),
      loader: 'jsx',
      resolveDir,
    },
    bundle: true,
    loader: { '.css': 'empty' },
    outfile: join(temp, 'fixture.js'),
    plugins: [{
      name: 'chat-scroll-fixtures',
      setup(builder) {
        builder.onResolve({ filter: /\/[^/]+$/ }, ({ path }) => {
          const name = path.split('/').at(-1);
          if (Object.hasOwn(fixtures, name)) return { path: name, namespace: 'fixture' };
        });
        builder.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
          contents: fixtures[path], resolveDir, loader: 'jsx',
        }));
      },
    }],
  });
  const styles = await readFile(new URL('src/index.css', webapp), 'utf8');
  const html = join(temp, 'index.html');
  await writeFile(html, `<!doctype html><html lang="en"><meta charset="utf-8">
    <style>${styles}
      #root { display: flex; flex-direction: column; height: 460px; width: 560px; }
    </style>
    <div id="root"></div><pre id="results"></pre><script src="fixture.js"></script>
  </html>`);
  const result = spawnSync(browser, [
    '--headless', '--disable-background-networking', '--disable-gpu',
    '--no-first-run', '--no-default-browser-check', '--run-all-compositor-stages-before-draw',
    '--virtual-time-budget=8000', '--dump-dom', `--user-data-dir=${join(temp, 'profile')}`,
    pathToFileURL(html).href,
  ], { encoding: 'utf8', timeout: 20000, maxBuffer: 2 * 1024 * 1024 });
  const report = result.stdout?.match(/<pre id="results">([\s\S]*?)<\/pre>/)?.[1]?.trim();
  const output = report || result.stderr?.trim() || String(result.error ?? result.signal ?? result.status);
  const summary = `${output}\nRunner time: ${Math.round(performance.now() - startedAt)} ms`;
  console.log(summary);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  await writeFile(new URL(`results/${stamp}-web.log`, import.meta.url), `${summary}\n`);
  if (result.status !== 0 || !report?.includes('ALL PASSED')) process.exitCode = 1;
} finally {
  await rm(temp, { recursive: true });
}
