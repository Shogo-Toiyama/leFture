import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';

const folder = new URL('./', import.meta.url);
const webapp = new URL('../../../webapp/', folder);
const resolveDir = fileURLToPath(webapp);
const require = createRequire(new URL('package.json', webapp));
const { build } = require('esbuild');

const fixtures = {
  LanguageContext: 'export const useLanguage = () => ({ t: (key) => key });',
  useLectureTopics: 'export const useLectureTopics = () => ({ topics: window.fixtureTopics });',
  useReviewCards: 'export const useReviewCards = () => ({ cards: window.fixtureCards });',
  useCourse: 'export const useCourse = () => ({ course: null });',
  useTopicImageUrls: 'export const useTopicImageUrls = () => ({});',
  lectures: 'export const getLecture = async () => null;',
  ChatPanelContext: 'export const useChatScreen = () => {}; export const useChatPanel = () => null;',
  AppTopbar: 'export const AppTopbar = () => null;',
  TranscriptSheet: 'export const TranscriptSheet = () => null;',
  supabase: 'export const supabase = new Proxy({}, { get() { throw Error("Unexpected backend request"); } });',
};

const browser = process.env.CHROME_BIN ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const temp = await mkdtemp(join(tmpdir(), 'web-review-card-'));
const startedAt = performance.now();

try {
  await build({
    absWorkingDir: resolveDir,
    stdin: { contents: await readFile(new URL('fixture.jsx', folder), 'utf8'), loader: 'jsx', resolveDir },
    bundle: true,
    outfile: join(temp, 'fixture.js'),
    loader: { '.css': 'empty' },
    plugins: [{
      name: 'review-card-fixtures',
      setup(builder) {
        builder.onResolve(
          { filter: /\/(LanguageContext|useLectureTopics|useReviewCards|useCourse|useTopicImageUrls|lectures|ChatPanelContext|AppTopbar|TranscriptSheet|supabase)$/ },
          ({ path }) => ({ path: path.split('/').at(-1), namespace: 'fixture' }),
        );
        builder.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
          contents: fixtures[path], resolveDir, loader: 'js',
        }));
      },
    }],
  });
  const styles = (await readFile(new URL('src/index.css', webapp), 'utf8')).replace(/^@import[^;]*;/gm, '');
  const html = join(temp, 'index.html');
  await writeFile(html, `<!doctype html><html lang="ja"><meta charset="utf-8">
    <style>${styles}</style>
    <div id="root"></div><pre id="results" hidden></pre><script src="fixture.js"></script>
  </html>`);
  const result = spawnSync(browser, [
    '--headless', '--disable-background-networking', '--disable-gpu', '--no-first-run',
    '--no-default-browser-check', '--run-all-compositor-stages-before-draw', '--window-size=480,900',
    '--virtual-time-budget=8000', '--dump-dom', `--user-data-dir=${join(temp, 'profile')}`, pathToFileURL(html).href,
  ], { encoding: 'utf8', timeout: 20000, maxBuffer: 2 * 1024 * 1024 });
  const report = result.stdout?.match(/<pre id="results"[^>]*>([\s\S]*?)<\/pre>/)?.[1] ?? '';
  const outcome = report.trim() || String(result.error ?? (result.stderr || `Chrome exited with ${result.signal ?? result.status}`));
  const summary = `${outcome}\nElapsed: ${Math.round(performance.now() - startedAt)} ms\n`;
  console.log(summary);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  await writeFile(new URL(`results/${stamp}.log`, folder), summary);
  if (result.status !== 0 || !report.includes('ALL PASSED')) process.exitCode = 1;
} finally {
  await rm(temp, { recursive: true });
}
