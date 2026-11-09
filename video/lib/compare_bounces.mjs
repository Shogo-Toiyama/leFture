// Render the bounce comparison view for several bounce counts in one page load (90 s cap).
//   node lib/compare_bounces.mjs <out prefix> [spp] [w] [h] [bounces]
import fs from 'node:fs';
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';

const [prefix, spp = '24', w = '360', h = '640', list = '6,3,1', extra = ''] = process.argv.slice(2);
const CAP_MS = 90_000;
const server = await startServer(0);
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu', '--no-first-run'],
});
const kill = setTimeout(async () => {
  console.error('[compare] hit the 90s cap — stopping');
  await browser.close().catch(() => {});
  server.close();
  process.exit(2);
}, CAP_MS);
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (m.text().startsWith('[bench]')) console.log(m.text()); });
  page.on('pageerror', (e) => console.error('[page error]', e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/test/lecture/?capture=1&spp=${spp}&w=${w}&h=${h}&compare=${list}${extra ? '&' + extra : ''}`);
  await page.waitForFunction('window.__compare', { timeout: CAP_MS, polling: 500 });
  const res = await page.evaluate(() => window.__compare);
  const report = {};
  for (const [b, { ms, png }] of Object.entries(res)) {
    const file = `${prefix}_${b}.png`;
    fs.writeFileSync(file, Buffer.from(png.split(',')[1], 'base64'));
    report[`bounces${b}`] = { ms, file };
  }
  fs.writeFileSync(`${prefix}.json`, JSON.stringify({ spp: Number(spp), size: `${w}x${h}`, ...report }, null, 2));
  console.log(JSON.stringify(report));
} finally {
  clearTimeout(kill);
  await browser.close().catch(() => {});
  server.close();
}
