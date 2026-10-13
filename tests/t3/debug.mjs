import { chromium } from '@playwright/test';

const b = await chromium.launch();
const page = await b.newPage({ viewport: { width: 1280, height: 800 } });
page.on('console', (m) => console.log('CON:', m.text().slice(0, 250)));
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 400)));
await page.goto('http://127.0.0.1:8824/t3/index.html');
await page.waitForTimeout(8000);
const c = await page.evaluate(() => document.querySelectorAll('canvas').length);
console.log('CANVASES:', c);
await b.close();
