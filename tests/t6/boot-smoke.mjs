// Leg D task 1: boots inkscape.wasm in GUI mode (broadway) in node.
// callMain must RETURN (main-loop-yield patch), bridge_frame must pump,
// the daemon must produce browser-bound bytes (window created + drawn).
// usage: node boot-smoke.mjs [module.js]
import { join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

const modulePath = process.argv[2] ?? 'build/inkscape/bin/inkscape.js';
const factory = (await import(pathToFileURL(modulePath))).default;
const m = await factory({
  noInitialRun: true,
  locateFile: f => join(dirname(modulePath), f),
  print: t => console.log(t),
  printErr: t => console.error(t),
});

m.callMain([]);         // must return (main-loop-yield patch); gtk_init inside
                        // creates the daemon (bridge_daemon_init)
console.log('boot-smoke: callMain returned');
m._bridge_js_connect(); // browser client attaches AFTER the daemon exists
                        // (bridge.c no-ops if bserver is still NULL)

let bytes = 0;
const frames = 300; // ~5s of "rAF" at 60fps
for (let i = 0; i < frames; i++) {
  m._bridge_frame();                          // one nonblocking iteration
  bytes += Math.max(0, m._bridge_js_poll());  // daemon -> "browser" bytes
}
console.log(`boot-smoke: ${frames} iterations, ${bytes} daemon->browser bytes`);
if (bytes <= 0) {
  console.error('boot-smoke FAIL: daemon never sent bytes — window was never created/drawn');
  process.exit(1);
}
console.log('boot-smoke PASS');
process.exit(0);
