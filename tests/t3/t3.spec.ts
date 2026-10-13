import { test, expect } from '@playwright/test';

test('T3: gtkmm signal fires and cairo paints', async ({ page }) => {
  const fired: string[] = [];
  page.on('console', (m) => { if (m.text().includes('signal fired')) fired.push(m.text()); });

  await page.goto('/t3/index.html');
  await page.waitForSelector('canvas', { timeout: 20000 });
  await page.waitForTimeout(1500);

  // cairo red rectangle (0.85,0.1,0.1) somewhere in the window canvas;
  // scan the full surface so the check doesn't depend on CSD margins
  const red = await page.evaluate(() => {
    let n = 0;
    for (const c of document.querySelectorAll('canvas')) {
      const el = c as HTMLCanvasElement;
      const ctx = el.getContext('2d')!;
      if (!ctx || el.width < 200 || el.height < 80) continue;
      const d = ctx.getImageData(0, 0, el.width, el.height).data;
      for (let i = 0; i < d.length; i += 4)
        if (d[i] > 180 && d[i + 1] < 100 && d[i + 2] < 100) n++;
    }
    return n;
  });
  expect(red).toBeGreaterThan(1000);

  // button event window center, surface-relative (see hello.cpp header)
  const rect = await page.evaluate(() => {
    const c = document.querySelector('canvas') as HTMLCanvasElement;
    const r = c.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  });
  expect(rect.w).toBeGreaterThan(300); // content + CSD margins
  await page.mouse.click(rect.x + 96, rect.y + 200);
  await expect.poll(() => fired.length, { timeout: 10000 }).toBeGreaterThan(0);

  await page.screenshot({ path: '../build/t3/t3-shot.png' });
});
