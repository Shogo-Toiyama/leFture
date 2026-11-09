// Light path-tracer benchmark: one Chrome, one page load, small canvas, hard 90 s cap.
//   node lib/bench_light.mjs <out.json> [w] [h]
import fs from 'node:fs';
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';

const [out, w = '270', h = '480'] = process.argv.slice(2);
const CAP_MS = 90_000;
const started = Date.now();
const server = await startServer(0);
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu', '--no-first-run'],
});
const kill = setTimeout(async () => {
  console.error(`[bench] hit the ${CAP_MS / 1000}s cap — stopping`);
  await browser.close().catch(() => {});
  server.close();
  process.exit(2);
}, CAP_MS);
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (m.text().startsWith('[bench]')) console.log(m.text()); });
  page.on('pageerror', (e) => console.error('[page error]', e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/test/lecture/?capture=1&bench=1&w=${w}&h=${h}`);
  await page.waitForFunction('window.__bench', { timeout: CAP_MS, polling: 500 });
  const result = await page.evaluate(() => window.__bench);
  result.total_seconds = Number(((Date.now() - started) / 1000).toFixed(1));
  fs.writeFileSync(out, JSON.stringify(result, null, 2));
  console.log(`[bench] done in ${result.total_seconds}s → ${out}`);
} finally {
  clearTimeout(kill);
  await browser.close().catch(() => {});
  server.close();
}
