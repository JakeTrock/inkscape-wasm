import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';

test('T8: icons render, zero boot errors, non-occluded canvas, save on fresh canvas', async ({ page }) => {
  const consoleLines: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', m => consoleLines.push(m.text()));
  page.on('pageerror', e => pageErrors.push(String(e)));

  await page.goto('/harness/index.html');
  await page.waitForSelector('#stage-runtime[data-state=ok]', { timeout: 60000 });
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForTimeout(2500);

  // 1. Zero CRITICAL, WARNING, pthread_create, or pageerror messages
  const badConsole = consoleLines.filter(l => /CRITICAL|WARNING|pthread_create/i.test(l));
  expect(pageErrors, `pageErrors: ${JSON.stringify(pageErrors)}`).toEqual([]);
  expect(badConsole, `badConsole: ${JSON.stringify(badConsole)}`).toEqual([]);

  // 2. Canvas not occluded by #toolbar / #stagebar, and icons rendered in toolbox & topbars
  const uiFacts = await page.evaluate(() => {
    const stageBottom = document.getElementById('stagebar')!.getBoundingClientRect().bottom;
    const big = [...document.querySelectorAll('canvas')].sort(
      (a: any, b: any) => b.width * b.height - a.width * a.height)[0] as HTMLCanvasElement;
    const rect = big.getBoundingClientRect();
    const d = big.getContext('2d')!.getImageData(0, 0, big.width, big.height).data;

    // Sample background reference in left toolbox (x=2, y=100)
    const bgIdx = (100 * big.width + 2) * 4;
    const bgR = d[bgIdx], bgG = d[bgIdx + 1], bgB = d[bgIdx + 2];
    const differs = (x: number, y: number) => {
      const i = (y * big.width + x) * 4;
      return Math.abs(d[i] - bgR) + Math.abs(d[i + 1] - bgG) + Math.abs(d[i + 2] - bgB) > 60;
    };

    // Count 12 vertical slots (each 32px tall) in left toolbox column x in [6..30], y in [100..484]
    let leftSlotsWithIcons = 0;
    for (let slot = 0; slot < 12; slot++) {
      let fgPixels = 0;
      const yStart = 100 + slot * 32;
      for (let y = yStart; y < yStart + 32; y++) {
        for (let x = 6; x <= 30; x++) {
          if (differs(x, y)) fgPixels++;
        }
      }
      if (fgPixels >= 15) leftSlotsWithIcons++;
    }

    // Count 16 horizontal slots (each 32px wide) in top toolbars x in [10..522], y in [30..95]
    let topSlotsWithIcons = 0;
    for (let slot = 0; slot < 16; slot++) {
      let fgPixels = 0;
      const xStart = 10 + slot * 32;
      for (let y = 30; y <= 95; y++) {
        for (let x = xStart; x < xStart + 32; x++) {
          if (differs(x, y)) fgPixels++;
        }
      }
      if (fgPixels >= 15) topSlotsWithIcons++;
    }

    // Verify top-right titlebar has NO close/minimize/maximize button glyphs (y in [4..32], x in [width-120..width-4])
    let topRightButtons = 0;
    for (let y = 4; y <= 32; y++) {
      for (let x = big.width - 120; x < big.width - 4; x++) {
        if (differs(x, y)) topRightButtons++;
      }
    }

    return {
      stageBottom: Math.round(stageBottom),
      canvasTop: Math.round(rect.top),
      canvasLeft: Math.round(rect.left),
      leftSlotsWithIcons,
      topSlotsWithIcons,
      topRightButtons,
    };
  });
  console.log('T8 uiFacts:', JSON.stringify(uiFacts));
  writeFileSync('../build/t8/t8-facts.json', JSON.stringify(uiFacts, null, 2));

  expect(uiFacts.canvasTop).toBeGreaterThanOrEqual(uiFacts.stageBottom);
  expect(uiFacts.leftSlotsWithIcons).toBeGreaterThanOrEqual(8);
  expect(uiFacts.topSlotsWithIcons).toBeGreaterThanOrEqual(8);
  expect(uiFacts.topRightButtons).toBe(0);

  // 2b. Verify File, Edit, View, Layer, Object dropdown menus open full-sized popup surfaces
  const menuY = uiFacts.canvasTop + 50;
  await page.mouse.click(uiFacts.canvasLeft + 20, menuY); // File
  await page.waitForTimeout(500);
  for (const [name, xOff] of [['File', 20], ['Edit', 60], ['View', 100], ['Layer', 150], ['Object', 205]] as const) {
    await page.mouse.move(uiFacts.canvasLeft + xOff, menuY);
    await page.waitForTimeout(400);
    const popup = await page.evaluate(() => {
      const s = Object.values((window as any).surfaces).find((p: any) => p.visible && p.id !== 1) as any;
      return s ? { id: s.id, w: s.width, h: s.height } : null;
    });
    expect(popup, `${name} dropdown popup`).not.toBeNull();
    expect(popup!.w, `${name} dropdown width`).toBeGreaterThan(200);
    expect(popup!.h, `${name} dropdown height`).toBeGreaterThan(200);
  }
  // Close the open menu by clicking the canvas body before drawing
  await page.mouse.click(uiFacts.canvasLeft + 260, uiFacts.canvasTop + 240);
  await page.waitForTimeout(400);

  // 3. Draw a rectangle on the fresh default canvas (no Open SVG first) and Save
  const x0 = uiFacts.canvasLeft + 260, y0 = uiFacts.canvasTop + 240;
  const runActions = (actions: string) => page.evaluate(a => {
    const m: any = (window as any).__bridge_mod;
    const ptr = m._malloc(a.length + 1);
    m.HEAPU8.set(new TextEncoder().encode(a), ptr);
    m.HEAPU8[ptr + a.length] = 0;
    m._inkscape_run_actions(ptr);
    m._free(ptr);
  }, actions);

  let drew = false;
  for (let attempt = 0; attempt < 2 && !drew; attempt++) {
    await page.mouse.click(x0, y0);
    await page.waitForTimeout(800);
    await page.keyboard.press('F4');
    await page.waitForTimeout(800);
    await page.mouse.move(x0, y0);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) {
      await page.mouse.move(x0 + Math.round(180 * i / 10), y0 + Math.round(120 * i / 10));
    }
    await page.mouse.up();
    await page.waitForTimeout(2000);
    await runActions('export-filename:/home/web_user/dbg8.svg;export-do');
    drew = await page.evaluate(() => {
      const m: any = (window as any).__bridge_mod;
      const d = new TextDecoder().decode(m.FS.readFile('/home/web_user/dbg8.svg'));
      return /<rect\b/.test(d);
    });
  }
  expect(drew, 'fresh canvas drag produced a <rect>').toBe(true);

  await page.click('#btn-save');
  await page.waitForTimeout(1500);
  const saved = await page.evaluate(() => {
    const m: any = (window as any).__bridge_mod;
    const p = (window as any).__doc_path;
    return { path: p, svg: p ? new TextDecoder().decode(m.FS.readFile(p)) : '' };
  });
  expect(saved.path).toBe('/home/web_user/documents/drawing.svg');
  expect(saved.svg).toContain('<rect');
  const postMenuBadConsole = consoleLines.filter(l => /CRITICAL|WARNING|pthread_create/i.test(l));
  expect(postMenuBadConsole, `postMenuBadConsole: ${JSON.stringify(postMenuBadConsole)}`).toEqual([]);
  writeFileSync('../build/t8/t8-saved.svg', saved.svg);
  await page.screenshot({ path: '../build/t8/t8-shot.png' });
});
