// Open a scene page and print its console for N seconds (debugging scene setup).
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';
const [scene, secs = '90', query = ''] = process.argv.slice(2);
const server = await startServer(0);
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu'] });
const page = await browser.newPage();
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
page.on('console', (m) => console.log(ts(), '[console]', m.type(), m.text().slice(0, 400)));
page.on('pageerror', (e) => console.log(ts(), '[pageerror]', e.message));
page.on('requestfailed', (r) => console.log(ts(), '[requestfailed]', r.url(), r.failure()?.errorText));
page.on('response', (r) => { if (r.status() >= 400) console.log(ts(), '[http]', r.status(), r.url()); });
await page.goto(`http://127.0.0.1:${server.address().port}/${scene}/?capture=1&${query}`);
const end = Date.now() + Number(secs) * 1000;
while (Date.now() < end) {
  if (await page.evaluate(() => window.__ready === true)) { console.log(ts(), 'READY'); break; }
  await new Promise((r) => setTimeout(r, 1000));
}
await browser.close(); server.close();
