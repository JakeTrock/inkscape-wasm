// T5 driver: run inkscape.wasm headless in node, export an SVG to PNG.
// usage: node driver.mjs <module.js> <in-fs-svg> <out-host-png>
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const [, , modulePath, svg, out] = process.argv;
if (!modulePath || !svg || !out) {
  console.error('usage: node driver.mjs <module.js> <in-fs-svg> <out-host-png>');
  process.exit(2);
}

const factory = (await import(pathToFileURL(modulePath))).default;
const m = await factory({
  noInitialRun: true,
  print: t => console.log(t),
  printErr: t => console.error(t),
});

try {
  m.callMain(['--batch-process', '--actions',
    `file-open:${svg}; export-filename:/out.png; export-do; file-close`]);
} catch (e) {
  console.error(`driver: inkscape aborted: ${e && e.message || e}`);
  process.exit(1);
}

try {
  writeFileSync(out, m.FS.readFile('/out.png'));
  console.log(`driver: wrote ${out} (${m.FS.stat('/out.png').size} bytes)`);
} catch (e) {
  console.error(`driver: no /out.png produced: ${e && e.message || e}`);
  process.exit(1);
}
process.exit(0); // runtime stays alive without EXIT_RUNTIME; we decide
