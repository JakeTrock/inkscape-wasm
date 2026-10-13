import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';

// T7 gate (v1 acceptance): scripted GUI session — open fixture, switch to the
// rect tool (F4 accel — text-only model can't read goldens for toolbar coords,
// spec deviation recorded in the plan), draw a rectangle with a real canvas
// click-drag, Save via the harness toolbar, assert the SVG, Export PNG.
test('T7: draw rect, save, export', async ({ page }) => {
  await page.goto('/harness/index.html');
  await page.waitForSelector('#stage-runtime[data-state=ok]', { timeout: 60000 });
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForTimeout(1500);

  // Open the fixture (harness toolbar -> file-open action)
  await page.setInputFiles('#file-input', 't7-rect.svg');
  await page.waitForFunction('window.__doc_path !== null', null, { timeout: 30000 });
  await page.waitForTimeout(1500); // let the doc window paint

  // Rect tool via accel (falls back to the tool-switch action if this proves flaky)
  await page.keyboard.press('F4');
  await page.waitForTimeout(300);

  // Draw on the (biggest) broadway canvas: real mouse drag, 200x150 px
  const big = await page.evaluate(() => {
    const c = [...document.querySelectorAll('canvas')].sort(
      (a: any, b: any) => b.width * b.height - a.width * a.height)[0]
      as HTMLCanvasElement;
    const r = c.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  });
  const x0 = Math.round(big.x + 220), y0 = Math.round(big.y + 200);
  await page.mouse.move(x0, y0);
  await page.mouse.down();
  for (let i = 1; i <= 10; i++)
    await page.mouse.move(x0 + Math.round(200 * i / 10), y0 + Math.round(150 * i / 10));
  await page.mouse.up();
  await page.waitForTimeout(1500);

  // Save via toolbar -> file-save action -> file is in the wasm FS
  await page.click('#btn-save');
  await page.waitForTimeout(1500);
  const svg = await page.evaluate(() => {
    const m = window.__bridge_mod;
    return new TextDecoder().decode(m.FS.readFile(window.__doc_path));
  });
  writeFileSync('../build/t7/t7-saved.svg', svg);

  expect(svg).toContain('<rect');
  const rect = svg.match(/<rect[^>]*>/)?.[0] ?? '';
  console.log('T7 rect element:', rect);
  const num = (attr: string) => {
    const m = rect.match(new RegExp(`${attr}="([0-9.eE+-]+)`));
    return m ? Number(m[1]) : NaN;
  };
  // 200x150 drag at zoom ~= 1 — loose bounds, zoom/scroll may scale
  expect(num('width')).toBeGreaterThan(80);
  expect(num('width')).toBeLessThan(400);
  expect(num('height')).toBeGreaterThan(60);
  expect(num('height')).toBeLessThan(320);

  // Export PNG via toolbar -> export-do
  await page.click('#btn-export');
  await page.waitForTimeout(2000);
  const png = await page.evaluate(() =>
    window.__bridge_mod.FS.readFile('/home/web_user/export.png'));
  writeFileSync('../build/t7/t7-wasm.png', png);
  expect(png.length).toBeGreaterThan(1000);

  await page.screenshot({ path: '../build/t7/t7-shot.png' });
});
