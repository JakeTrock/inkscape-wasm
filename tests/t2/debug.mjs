import { chromium } from '@playwright/test';

const b = await chromium.launch();
const page = await b.newPage({ viewport: { width: 1280, height: 800 } });
const clicks = [];
page.on('console', (m) => {
  const t = m.text();
  if (t.includes('button clicked')) clicks.push(t);
  if (t.startsWith('SEND:') || t.startsWith('DBG:') || t.startsWith('BRIDGE:') || t.startsWith('GEOM') || t.includes('button-')) console.log(t.slice(0, 200));
});
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 300)));
await page.goto('http://127.0.0.1:8823/t2/index.html');
await page.waitForTimeout(3000);

// instrument input path
await page.evaluate(() => {
  const out = [];
  out.push('onmousedown installed: ' + (typeof document.onmousedown));
  out.push('active: ' + window.active);
  out.push('inputSocket: ' + (window.inputSocket ? 'set' : 'NULL'));
  const s = window.surfaces || {};
  for (const k of Object.keys(s)) {
    const su = s[k];
    out.push(`surface ${k}: x=${su.x} y=${su.y} w=${su.width} h=${su.height}` +
      (su.canvas ? ` canvas=${su.canvas.width}x${su.canvas.height} pos=${su.canvas.style.left},${su.canvas.style.top}` : ''));
  }
  if (window.BridgeSocket && BridgeSocket.prototype.send) {
    const orig = BridgeSocket.prototype.send;
    BridgeSocket.prototype.send = function (data) {
      const v = new DataView(data);
      const args = [];
      for (let i = 0; i * 4 < v.byteLength; i++) args.push(v.getInt32(i * 4, false));
      console.log('SEND: ' + JSON.stringify(args));
      return orig.call(this, data);
    };
    out.push('send wrapped');
  }
  console.log('DBG: ' + out.join(' | '));
});

// where would the click land?
const at = await page.evaluate(() => {
  const el = document.elementFromPoint(44, 117);
  return el ? `${el.tagName} ${el.width || ''} surface=${!!el.surface}` : 'nothing';
});
console.log('DBG: elementFromPoint(44,117):', at);

await page.mouse.move(300, 300);
await page.mouse.click(70, 177);
await page.waitForTimeout(1500);
console.log('CLICKS AFTER (70,177):', clicks.length);

// sweep a few candidates if nothing
if (clicks.length === 0) {
  const pts = [[70, 177], [96, 200], [70, 160], [100, 210]];
  for (const [x, y] of pts) {
    await page.mouse.click(x, y);
    await page.waitForTimeout(700);
    if (clicks.length) break;
  }
  console.log('CLICKS AFTER SWEEP:', clicks.length);
}
await b.close();
