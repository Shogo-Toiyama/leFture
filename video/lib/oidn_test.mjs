// Denoiser comparison for test/lecture (small canvas, one page, 90 s cap).
//   node lib/oidn_test.mjs <out prefix> [w] [h]
import fs from 'node:fs';
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';

const [prefix, w = '360', h = '640'] = process.argv.slice(2);
const CAP_MS = 90_000;
const server = await startServer(0);
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu', '--enable-unsafe-webgpu', '--no-first-run'],
});
const kill = setTimeout(async () => {
  console.error('[oidn] hit the 90s cap — stopping');
  await browser.close().catch(() => {});
  server.close();
  process.exit(2);
}, CAP_MS);
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (m.text().startsWith('[oidn]')) console.log(m.text()); });
  page.on('pageerror', (e) => console.error('[page error]', e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/test/lecture/?capture=1&oidnExp=1&w=${w}&h=${h}`);
  await page.waitForFunction('window.__oidn', { timeout: CAP_MS, polling: 500 });
  const res = await page.evaluate(() => window.__oidn);
  if (res.error) throw new Error(res.error);
  for (const [k, v] of Object.entries(res)) {
    if (typeof v === 'string' && v.startsWith('data:image/png')) fs.writeFileSync(`${prefix}_${k}.png`, Buffer.from(v.split(',')[1], 'base64'));
  }
  fs.writeFileSync(`${prefix}.json`, JSON.stringify({ size: `${w}x${h}`, timings_ms: res.timings }, null, 2));
  console.log('[oidn] saved', JSON.stringify(res.timings));
} finally {
  clearTimeout(kill);
  await browser.close().catch(() => {});
  server.close();
}
