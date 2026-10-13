import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';

// T6 gate: full inkscape GUI boots in the harness page — broadway window
// painted (toolbox column + white canvas body detectable as pixel stats),
// screenshot + textual geometry dump as artifacts (never eyeballed: text-only
// model rule; all assertions are numbers).
test('T6: inkscape GUI boots — chrome, toolbox, canvas', async ({ page }) => {
  const consoleLines: string[] = [];
  page.on('console', m => consoleLines.push(m.text()));

  await page.goto('/harness/index.html');
  await page.waitForSelector('#stage-runtime[data-state=ok]', { timeout: 60000 });
  await page.waitForSelector('#stage-broadway[data-state=ok]', { timeout: 30000 });
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForTimeout(2500); // settle a few frames

  const facts = await page.evaluate(() => {
    const canvases: any[] = [];
    for (const c of document.querySelectorAll('canvas')) {
      const r = c.getBoundingClientRect();
      canvases.push({ x: Math.round(r.x), y: Math.round(r.y),
                      w: Math.round(r.width), h: Math.round(r.height),
                      px: c.width, py: c.height });
    }
    const big = [...document.querySelectorAll('canvas')].sort(
      (a: any, b: any) => b.width * b.height - a.width * a.height)[0] as HTMLCanvasElement;
    const d = big.getContext('2d')!.getImageData(0, 0, big.width, big.height).data;
    const dark = (x: number, y: number) => {
      const i = (y * big.width + x) * 4;
      return d[i] < 128 && d[i + 1] < 128 && d[i + 2] < 128;
    };
    let toolDark = 0, bodyLight = 0;
    for (let y = 0; y < big.height; y += 4) {
      for (let x = 0; x < 40; x += 2) if (dark(x, y)) toolDark++;
      for (let x = 60; x < Math.min(600, big.width); x += 8) {
        const i = (y * big.width + x) * 4;
        if (d[i] > 235 && d[i + 1] > 235 && d[i + 2] > 235) bodyLight++;
      }
    }
    return { canvases, tallies: { toolDark, bodyLight } };
  });
  console.log('T6 facts:', JSON.stringify(facts));
  writeFileSync('../build/t6/t6-geom.json', JSON.stringify(facts, null, 2));

  const big = facts.canvases.reduce((a: any, b: any) => (a.w * a.h > b.w * b.h ? a : b));
  expect(big.w).toBeGreaterThan(800);   // inkscape main window is large
  expect(big.h).toBeGreaterThan(500);
  expect(facts.tallies.toolDark).toBeGreaterThan(30);    // left icon bar painted
  expect(facts.tallies.bodyLight).toBeGreaterThan(2000); // white drawing area

  await page.screenshot({ path: '../build/t6/t6-shot.png' });
});
