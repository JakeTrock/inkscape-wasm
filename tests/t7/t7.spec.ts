import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';

// T7 gate (v1 acceptance): scripted GUI session — open fixture, switch to the
// rect tool (F4 accel — text-only model can't read goldens for toolbar coords,
// spec deviation recorded in the plan), draw a rectangle with a real canvas
// click-drag, Save via the harness toolbar, assert the SVG, Export PNG.
test('T7: draw rect, save, export', async ({ page }) => {
  page.on('console', m => console.log('[page]', m.text().slice(0, 300)));
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 300)));
  await page.goto('/harness/index.html');
  await page.waitForSelector('#stage-runtime[data-state=ok]', { timeout: 60000 });
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForTimeout(1500);

  // Open the fixture (harness toolbar -> file-open action)
  await page.setInputFiles('#file-input', 'fixtures/t7-rect.svg');
  await page.waitForFunction('window.__doc_path !== null', null, { timeout: 30000 });
  await page.waitForTimeout(2000); // let the doc window paint

  // Click the canvas first: the broadway daemon drops key events until a
  // button press focuses the window (see findings, Leg D/E).
  const big = await page.evaluate(() => {
    const c: any = [...document.querySelectorAll('canvas')].sort(
      (a: any, b: any) => b.width * b.height - a.width * a.height)[0];
    const r = c.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  });
  const x0 = Math.round(big.x + 220), y0 = Math.round(big.y + 200);

  const runActions = (actions: string) => page.evaluate(a => {
    const m: any = (window as any).__bridge_mod;
    const ptr = m._malloc(a.length + 1);
    m.HEAPU8.set(new TextEncoder().encode(a), ptr);
    m.HEAPU8[ptr + a.length] = 0;
    m._inkscape_run_actions(ptr);
    m._free(ptr);
  }, actions);
  const drag = async () => {
    await page.mouse.move(x0, y0);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++)
      await page.mouse.move(x0 + Math.round(200 * i / 10), y0 + Math.round(150 * i / 10));
    await page.mouse.up();
    await page.waitForTimeout(2000);
  };
  const hasNewRect = async () => {
    await runActions('export-filename:/home/web_user/dbg.svg;export-do');
    return await page.evaluate(() => {
      const m: any = (window as any).__bridge_mod;
      const d = new TextDecoder().decode(m.FS.readFile('/home/web_user/dbg.svg'));
      return /<rect[^>]*width="(?!800)/.test(d);
    });
  };

  // Rect tool via F4 accel; verify the drag produced a rect, retry once if
  // the keypress was dropped (daemon focus timing).
  let drew = false;
  for (let attempt = 0; attempt < 2 && !drew; attempt++) {
    await page.mouse.click(x0, y0); // focus
    await page.waitForTimeout(800);
    await page.keyboard.press('F4');
    await page.waitForTimeout(800);
    await drag();
    drew = await hasNewRect();
  }
  expect(drew, 'canvas drag produced a <rect>').toBe(true);

  // Save via document-save action -> file written in the wasm FS.
  // The saved doc must keep the fixture background AND contain the new rect
  // (a real Inkscape save rewrites the whole document).
  await runActions('document-save');
  await page.waitForTimeout(1500);
  const svg = await page.evaluate(() => {
    const m = window.__bridge_mod;
    return new TextDecoder().decode(m.FS.readFile(window.__doc_path));
  });
  writeFileSync('../build/t7/t7-saved.svg', svg);

  expect(svg).toContain('inkscape:version'); // real save stamp
  const rects = svg.match(/<rect[^>]*>/g) ?? [];
  console.log('T7 rects in saved doc:', rects);
  expect(rects.length).toBeGreaterThanOrEqual(2);
  const rect = rects.find(r => !r.includes('width="800"')) ?? '';
  const num = (attr: string) => {
    const m = rect.match(new RegExp(`${attr}="([0-9.eE+-]+)`));
    return m ? Number(m[1]) : NaN;
  };
  // 200x150 canvas drag at fit-to-page zoom (~0.57) — loose bounds
  expect(num('width')).toBeGreaterThan(80);
  expect(num('width')).toBeLessThan(400);
  expect(num('height')).toBeGreaterThan(60);
  expect(num('height')).toBeLessThan(320);

  // Export PNG via export-do
  await page.evaluate(() => document.getElementById('btn-export')!.click());
  await page.waitForTimeout(2000);
  const png = await page.evaluate(() =>
    window.__bridge_mod.FS.readFile('/home/web_user/documents/export.png'));
  writeFileSync('../build/t7/t7-wasm.png', png);
  expect(png.length).toBeGreaterThan(1000);

  await page.screenshot({ path: '../build/t7/t7-shot.png' });

  // IDBFS persistence: flush memory -> IndexedDB, hard-reload, and the
  // saved document (plus docPath restore) must survive the fresh boot.
  await page.evaluate(() => window.__fs_flushed);
  await page.reload();
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForFunction('window.__doc_path !== null', null, { timeout: 30000 });
  const svg2 = await page.evaluate(() =>
    new TextDecoder().decode(window.__bridge_mod.FS.readFile(window.__doc_path)));
  expect(svg2).toContain('inkscape:version');
  expect((svg2.match(/<rect/g) ?? []).length).toBeGreaterThanOrEqual(2);
  console.log('T7 persistence: doc survived reload at', await page.evaluate('window.__doc_path'));
});
