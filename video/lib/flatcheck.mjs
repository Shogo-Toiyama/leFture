// Render test/recording/flat.html for a state and place it next to the screenshot.
import fs from 'node:fs';
import puppeteer from 'puppeteer';
import { startServer } from './server.mjs';
const [state, out] = process.argv.slice(2);
const server = await startServer(0);
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
const page = await browser.newPage();
page.on('pageerror', (e) => console.error('[page error]', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/test/recording/flat.html?state=${state}`);
await page.waitForFunction('window.__flat', { timeout: 60000 });
const d = await page.evaluate(() => window.__flat);
fs.writeFileSync(out, Buffer.from(d.split(',')[1], 'base64'));
await browser.close(); server.close();
