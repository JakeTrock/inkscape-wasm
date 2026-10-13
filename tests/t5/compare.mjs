// T5 comparator: pixelmatch actual vs golden.
// usage: node compare.mjs <actual.png> <golden.png> <max-differing-fraction>
import { readFileSync } from 'node:fs';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

const [, , actual, golden, maxFrac] = process.argv;
const a = PNG.sync.read(readFileSync(actual));
const b = PNG.sync.read(readFileSync(golden));

if (a.width !== b.width || a.height !== b.height) {
  console.error(`SIZE MISMATCH: ${a.width}x${a.height} vs ${b.width}x${b.height}`);
  process.exit(1);
}

const diff = pixelmatch(a.data, b.data, null, a.width, a.height, {
  threshold: 0.1, // per-pixel YIQ color delta
});
const total = a.width * a.height;
const frac = diff / total;
console.log(`pixelmatch: ${diff}/${total} pixels differ (${(frac * 100).toFixed(3)}%), limit ${(maxFrac * 100).toFixed(1)}%`);
process.exit(frac <= Number(maxFrac) ? 0 : 1);
