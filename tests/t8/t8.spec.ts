import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';

test('T8: icons, menus, dialogs, tools, copy/paste, fresh-save, low-latency drag & zero errors', async ({ page }) => {
  const consoleLines: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', m => consoleLines.push(m.text()));
  page.on('pageerror', e => pageErrors.push(String(e)));

  await page.goto('/harness/index.html');
  await page.waitForSelector('#stage-runtime[data-state=ok]', { timeout: 60000 });
  await page.waitForSelector('canvas', { timeout: 90000 });
  await page.waitForSelector('#stage-frame[data-state=ok]', { timeout: 30000 });
  await page.waitForTimeout(2000);

  // 1. Zero CRITICAL, WARNING, pthread_create, or pageerror messages on boot
  const bootBad = consoleLines.filter(l => /CRITICAL|WARNING|pthread_create|Uncaught|RuntimeError/i.test(l));
  expect(pageErrors, `boot pageErrors: ${JSON.stringify(pageErrors)}`).toEqual([]);
  expect(bootBad, `boot badConsole: ${JSON.stringify(bootBad)}`).toEqual([]);

  // 2. Canvas not occluded by #toolbar / #stagebar, icons rendered, and no top-right window buttons
  const uiFacts = await page.evaluate(() => {
    const stageBottom = document.getElementById('stagebar')!.getBoundingClientRect().bottom;
    const big = [...document.querySelectorAll('canvas')].sort(
      (a: any, b: any) => b.width * b.height - a.width * a.height)[0] as HTMLCanvasElement;
    const rect = big.getBoundingClientRect();
    const d = big.getContext('2d')!.getImageData(0, 0, big.width, big.height).data;

    const bgIdx = (100 * big.width + 2) * 4;
    const bgR = d[bgIdx], bgG = d[bgIdx + 1], bgB = d[bgIdx + 2];
    const differs = (x: number, y: number) => {
      const i = (y * big.width + x) * 4;
      return Math.abs(d[i] - bgR) + Math.abs(d[i + 1] - bgG) + Math.abs(d[i + 2] - bgB) > 60;
    };

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
  expect(uiFacts.canvasTop).toBeGreaterThanOrEqual(uiFacts.stageBottom);
  expect(uiFacts.leftSlotsWithIcons).toBeGreaterThanOrEqual(8);
  expect(uiFacts.topSlotsWithIcons).toBeGreaterThanOrEqual(8);
  expect(uiFacts.topRightButtons).toBe(0);

  // 3. Dropdown menus (File, Edit, View, Layer, Object, Path, Text, Filters, Extensions, Help)
  const menuY = uiFacts.canvasTop + 50;
  await page.mouse.click(uiFacts.canvasLeft + 20, menuY);
  await page.waitForTimeout(300);
  for (const [name, xOff] of [
    ['File', 20], ['Edit', 60], ['View', 100], ['Layer', 150], ['Object', 205],
    ['Path', 255], ['Text', 295], ['Filters', 345], ['Extensions', 405], ['Help', 475],
  ] as const) {
    await page.mouse.move(uiFacts.canvasLeft + xOff, menuY);
    await page.waitForTimeout(200);
    const popup = await page.evaluate(() => {
      const s = Object.values((window as any).surfaces).find((p: any) => p.visible && p.id !== 1) as any;
      return s ? { id: s.id, x: s.x, y: s.y, w: s.width, h: s.height } : null;
    });
    expect(popup, `${name} dropdown popup`).not.toBeNull();
    expect(popup!.w, `${name} dropdown width`).toBeGreaterThan(150);
    expect(popup!.h, `${name} dropdown height`).toBeGreaterThan(120);
  }
  // Move pointer inside open popup and click to close/activate without TypeError on deleted surface
  await page.mouse.move(uiFacts.canvasLeft + 480, menuY + 30);
  await page.waitForTimeout(100);
  await page.mouse.click(uiFacts.canvasLeft + 260, uiFacts.canvasTop + 240);
  await page.waitForTimeout(200);

  const runActions = (actions: string) => page.evaluate(a => {
    const m: any = (window as any).__bridge_mod;
    const ptr = m._malloc(a.length + 1);
    m.HEAPU8.set(new TextEncoder().encode(a), ptr);
    m.HEAPU8[ptr + a.length] = 0;
    m._inkscape_run_actions(ptr);
    m._free(ptr);
  }, actions);

  // 4. Draw a rectangle on the fresh canvas, measure frame latency during drag, Copy & Paste, and Save
  const x0 = uiFacts.canvasLeft + 240, y0 = uiFacts.canvasTop + 220;
  let drew = false;
  let dragElapsedMs = 0;
  for (let attempt = 0; attempt < 2 && !drew; attempt++) {
    await page.mouse.click(x0, y0);
    await page.waitForTimeout(300);
    await page.keyboard.press('F4');
    await page.waitForTimeout(300);
    const t0 = Date.now();
    await page.mouse.move(x0, y0);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) {
      await page.mouse.move(x0 + Math.round(180 * i / 10), y0 + Math.round(120 * i / 10));
    }
    await page.mouse.up();
    dragElapsedMs = Date.now() - t0;
    await page.waitForTimeout(400);
    await runActions('export-filename:/home/web_user/dbg8.svg;export-do');
    drew = await page.evaluate(() => {
      const m: any = (window as any).__bridge_mod;
      const d = new TextDecoder().decode(m.FS.readFile('/home/web_user/dbg8.svg'));
      return /<rect\b/.test(d);
    });
  }
  expect(drew, 'fresh canvas drag produced a <rect>').toBe(true);
  expect(dragElapsedMs, '10-step drag latency').toBeLessThan(1000);

  // Copy & Paste the drawn rectangle -> should produce >= 2 <rect> elements
  await runActions('copy;paste');
  await page.waitForTimeout(300);

  await page.click('#btn-save');
  await page.waitForTimeout(800);
  const saved = await page.evaluate(() => {
    const m: any = (window as any).__bridge_mod;
    const p = (window as any).__doc_path;
    return { path: p, svg: p ? new TextDecoder().decode(m.FS.readFile(p)) : '' };
  });
  expect(saved.path).toBe('/home/web_user/documents/drawing.svg');
  expect((saved.svg.match(/<rect\b/g) ?? []).length).toBeGreaterThanOrEqual(2);

  // 5. Exercise dialogs (including Export, DocumentResources, FillStroke, Objects, Preferences, etc.)
  for (const dlg of [
    'Export', 'FillStroke', 'Objects', 'DocumentResources', 'AlignDistribute',
    'Transform', 'Text', 'Swatches', 'Symbols', 'Selectors', 'FilterEffects',
    'LivePathEffect', 'SVGFonts', 'Preferences', 'XMLEditor', 'UndoHistory',
  ]) {
    await runActions(`dialog-open:${dlg}`);
    await page.waitForTimeout(100);
  }

  // 6. Exercise previously-blocking/crashing file, template, help, and tool-switch actions
  for (const act of [
    'document-open', 'document-import', 'document-save-as', 'document-save-copy',
    'about', 'tutorial-basic', 'quit', 'document-new',
    'tool-switch:Pages', 'tool-switch:Node', 'tool-switch:Gradient', 'tool-switch:Rect',
  ]) {
    await runActions(act);
    await page.waitForTimeout(80);
  }

  // 7. Zero uncaught errors or CRITICALs across the entire session
  const sessionBad = consoleLines.filter(l => /CRITICAL|Uncaught|RuntimeError/i.test(l));
  expect(pageErrors, `session pageErrors: ${JSON.stringify(pageErrors)}`).toEqual([]);
  expect(sessionBad, `session badConsole: ${JSON.stringify(sessionBad)}`).toEqual([]);

  const summary = { ...uiFacts, dragElapsedMs, savedRects: (saved.svg.match(/<rect\b/g) ?? []).length };
  console.log('T8 summary:', JSON.stringify(summary));
  writeFileSync('../build/t8/t8-facts.json', JSON.stringify(summary, null, 2));
  writeFileSync('../build/t8/t8-saved.svg', saved.svg);
  await page.screenshot({ path: '../build/t8/t8-shot.png' });
});
