/* Inkscape WASM harness loader (spec 05). Boots the module, attaches the
 * broadway client, drives the main loop per rAF tick, and wires the toolbar.
 * Order matters: callMain (gtk_init -> daemon) BEFORE connect (needs daemon). */
'use strict';

const $ = id => document.getElementById(id);
const status = t => { $('status').textContent = t; };
const conlog = (t, err) => {
  const d = document.createElement('div');
  if (err) d.className = 'err';
  d.textContent = t;
  $('console').appendChild(d);
  $('console').scrollTop = $('console').scrollHeight;
};

function setStage(n, ok = true) {
  const el = $('stage-' + n);
  if (el) el.dataset.state = ok ? 'ok' : 'fail';
  if (ok) status(n + ' ✓');
}
window.__boot = { module: false, runtime: false, broadway: false,
                  window: false, frame: false };

const m = await Module({
  noInitialRun: true,
  locateFile: f => new URL(f, document.baseURI).href,
  print: t => conlog(t),
  printErr: t => conlog(t, true),
});
window.__bridge_mod = m;   // BridgeSocket / pumpDaemon (bridge.js)
window.__boot.module = true; setStage('module');

m.callMain([]);            // returns immediately (main-loop-yield patch)
window.__boot.runtime = true; setStage('runtime');

connect();                 // broadway.js -> new BridgeSocket() -> daemon
window.__boot.broadway = true; setStage('broadway');

const tick = () => {
  m._bridge_frame();       // one nonblocking main-loop pass
  pumpDaemon();            // daemon -> broadway.js frames
  if (!window.__boot.window && document.querySelector('canvas')) {
    window.__boot.window = true; setStage('window');
  }
  if (window.__boot.window) {
    window.__boot.frame = true; setStage('frame');
  }
  requestAnimationFrame(tick);
};
requestAnimationFrame(tick);
status('ready');

/* ---- toolbar (v1: in-memory FS + blob downloads; no IDBFS persistence
 * across reloads — spec-05 deviation, see plan) ---- */

let docPath = null;        // last-opened file; Save writes back to it
window.__doc_path = null;

$('file-input').addEventListener('change', async e => {
  const f = e.target.files[0];
  if (!f) return;
  const bytes = new Uint8Array(await f.arrayBuffer());
  docPath = '/home/web_user/' + f.name;
  m.FS.writeFile(docPath, bytes);
  window.__doc_path = docPath;
  runActions('file-open:' + docPath);
  status('opened ' + docPath);
  e.target.value = '';
});

$('btn-open').onclick = () => $('file-input').click();

$('btn-save').onclick = () => {
  if (!docPath) {
    status('Save: no file opened yet — Inkscape Save-As dialog opens instead');
    runActions('file-save');
    return;
  }
  runActions('file-save');
  download(docPath.split('/').pop(), m.FS.readFile(docPath), 'image/svg+xml');
  status('saved ' + docPath);
};

$('btn-export').onclick = () => {
  runActions('export-filename:/home/web_user/export.png;export-do');
  download('export.png', m.FS.readFile('/home/web_user/export.png'), 'image/png');
  status('exported export.png');
};

$('btn-reload').onclick = () => location.reload();

function runActions(actions) {
  const ptr = m._malloc(actions.length + 1);
  m.HEAPU8.set(new TextEncoder().encode(actions), ptr);
  m.HEAPU8[ptr + actions.length] = 0;
  m._inkscape_run_actions(ptr);
  m._free(ptr);
}

function download(name, bytes, type) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([bytes], { type }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

window.addEventListener('error', e => {
  conlog(`Uncaught: ${e.message}\n  ${e.filename}:${e.lineno}`, true);
  setStage(Object.entries(window.__boot).filter(([, v]) => !v)
    .map(([k]) => k).pop() || 'frame', false);
});
