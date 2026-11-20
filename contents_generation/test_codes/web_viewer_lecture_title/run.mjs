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
  LanguageContext: `import { ja } from './src/i18n/locales/ja';
    export const useLanguage = () => ({ t: (key) => ja[key] ?? key });`,
  useLectureTopics: 'export const useLectureTopics = () => ({ topics: window.fixtureTopics });',
  useReviewCards: 'export const useReviewCards = () => ({ cards: window.fixtureCards });',
  useCourse: 'export const useCourse = () => ({ course: null });',
  useTopicImageUrls: 'export const useTopicImageUrls = () => ({});',
  lectures: 'export const getLecture = async (id) => ({ id, ...window.fixtureLecture });',
  ChatPanelContext: 'export const useChatScreen = () => {}; export const useChatPanel = () => null;',
  useProfile: 'export const useProfile = () => ({ profile: null });',
  billing: 'export const getCreditSummary = async () => { throw Error("Fixture has no billing data"); };',
  artifacts: 'export const fetchArtifactObjectUrl = async () => { throw Error("Unexpected artifact request"); };',
  SystemRecordingContext: 'export const useSystemRecording = () => window.fixtureRecording;',
  UploadModalContext: 'export const useUploadModal = () => ({ isOpen: false, openUploadModal() {} });',
  useDeepNotes: 'export const useDeepNotes = () => ({ notes: window.fixtureNotes });',
  useDeepNoteFigures: 'export const useDeepNoteFigures = () => ({ figures: [] });',
  TranscriptSheet: 'export const TranscriptSheet = () => null;',
  supabase: 'export const supabase = new Proxy({}, { get() { throw Error("Unexpected backend request"); } });',
};

const browser = process.env.CHROME_BIN ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const temp = await mkdtemp(join(tmpdir(), 'web-viewer-title-'));
const startedAt = performance.now();

try {
  await build({
    absWorkingDir: resolveDir,
    stdin: { contents: await readFile(new URL('fixture.jsx', folder), 'utf8'), loader: 'jsx', resolveDir },
    bundle: true,
    outfile: join(temp, 'fixture.js'),
    loader: { '.css': 'empty' },
    plugins: [{
      name: 'viewer-title-fixtures',
      setup(builder) {
        builder.onResolve(
          { filter: /\/(LanguageContext|useLectureTopics|useReviewCards|useCourse|useTopicImageUrls|lectures|ChatPanelContext|useProfile|billing|artifacts|SystemRecordingContext|UploadModalContext|useDeepNotes|useDeepNoteFigures|TranscriptSheet|supabase)$/ },
          ({ path }) => {
            if (path.endsWith('/types/billing')) return;
            return { path: path.split('/').at(-1), namespace: 'fixture' };
          },
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
  const args = [
    '--headless', '--disable-background-networking', '--disable-gpu', '--no-first-run',
    '--no-default-browser-check', '--run-all-compositor-stages-before-draw', '--window-size=1280,900',
    '--virtual-time-budget=8000', '--dump-dom', `--user-data-dir=${join(temp, 'profile')}`, pathToFileURL(html).href,
  ];
  const results = [];
  let allPassed = true;
  for (const [name, windowSize] of [['desktop', '1280,900'], ['mobile', '500,900']]) {
    const result = spawnSync(browser, args.map((arg) => arg.startsWith('--window-size=') ? `--window-size=${windowSize}` : arg), {
      encoding: 'utf8', timeout: 20000, maxBuffer: 2 * 1024 * 1024,
    });
    const report = result.stdout?.match(/<pre id="results"[^>]*>([\s\S]*?)<\/pre>/)?.[1] ?? '';
    const outcome = report.trim() || String(result.error ?? (result.stderr || `Chrome exited with ${result.signal ?? result.status}`));
    results.push(`${name}\n${outcome}`);
    if (result.status !== 0 || !report.includes('ALL PASSED')) allPassed = false;
  }
  const summary = `${results.join('\n\n')}\nElapsed: ${Math.round(performance.now() - startedAt)} ms\n`;
  console.log(summary);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  await writeFile(new URL(`results/${stamp}.log`, folder), summary);
  if (!allPassed) process.exitCode = 1;
} finally {
  await rm(temp, { recursive: true });
}
