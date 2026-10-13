import { test, expect } from '@playwright/test';

test('T2: gtk hello world paints and click registers', async ({ page }) => {
  const clicks: string[] = [];
  page.on('console', (m) => { if (m.text().includes('button clicked')) clicks.push(m.text()); });

  await page.goto('/t2/index.html');
  await page.waitForSelector('canvas', { timeout: 20000 });
  await page.waitForTimeout(1500); // let a few frames paint

  // label text = dark pixels across all window canvases (broadway: one canvas
  // per surface, stacked; text is rasterized by pango into the window surface)
  const dark = await page.evaluate(() => {
    let n = 0;
    for (const c of document.querySelectorAll('canvas')) {
      const el = c as HTMLCanvasElement;
      const ctx = el.getContext('2d')!;
      if (!ctx || el.width === 0) continue;
      const d = ctx.getImageData(0, 0, el.width, el.height).data;
      for (let i = 0; i < d.length; i += 4)
        if (d[i] < 128 && d[i + 1] < 128 && d[i + 2] < 128) n++;
    }
    return n;
  });
  expect(dark).toBeGreaterThan(50);

  // button at (20,120) size (100,40) in the window at (0,0)
  await page.mouse.click(70, 140);
  await expect.poll(() => clicks.length, { timeout: 10000 }).toBeGreaterThan(0);

  await page.screenshot({ path: '../build/t2/t2-shot.png' });
});
