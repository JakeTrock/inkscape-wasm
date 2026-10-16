/* Inkscape WASM harness loader (spec 05). Boots the module, attaches the
 * broadway client, drives the main loop per rAF tick, and wires the toolbar.
 * Order matters: callMain (gtk_init -> daemon) BEFORE connect (needs daemon). */
'use strict';

const $ = id => document.getElementById(id);
const status = t => { $('status').textContent = t; };
const conlog = (t, err) => {
  const clean = String(t).replace(/\x1b\[[0-9;]*m/g, '');
  console.log(clean); // also to the browser console (tests capture it)
  const d = document.createElement('div');
  if (err === 'fatal' || (err && /CRITICAL|ERROR|Uncaught|RuntimeError/i.test(clean))) {
    d.className = 'err';
  }
  d.textContent = clean;
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
// Translate page mouse/touch coords by the #broadway top offset (52px) so
// CSS-shifted body > canvas receives exact window-relative coordinates.
window.getPositionsFromEvent = (ev, relativeId) => {
  const top = Math.round($('broadway').getBoundingClientRect().top);
  const res = window.getPositionsFromAbsCoord(ev.pageX, ev.pageY - top, relativeId);
  window.lastX = res.rootX;
  window.lastY = res.rootY;
  return res;
};
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

/* ---- toolbar ----
 * /home/web_user/documents is an IDBFS mount: opened/saved/exported files
 * persist in IndexedDB across page reloads. flush() mirrors memory -> IDB
 * after every write; fsLoaded restores the last session's document. */

let docPath = null;        // last-opened/saved file; Save writes back to it
let docOpened = false;
window.__doc_path = null;

const DOCS = '/home/web_user/documents';
m.FS.mkdirTree(DOCS);
m.FS.mount(m.FS.filesystems.IDBFS, {}, DOCS);
const fsLoaded = new Promise(res => m.FS.syncfs(true, res));
const flush = () => { window.__fs_flushed = new Promise(res => m.FS.syncfs(false, res)); };
fsLoaded.then(() => {
  // exactly one persisted svg -> resume the last session's document
  const svgs = m.FS.readdir(DOCS).filter(f => f.endsWith('.svg'));
  if (svgs.length === 1) { docPath = DOCS + '/' + svgs[0]; window.__doc_path = docPath; }
});

$('file-input').addEventListener('change', async e => {
  const f = e.target.files[0];
  if (!f) return;
  const bytes = new Uint8Array(await f.arrayBuffer());
  await fsLoaded;
  docPath = DOCS + '/' + f.name;
  docOpened = true;
  m.FS.writeFile(docPath, bytes);
  window.__doc_path = docPath;
  flush();
  runActions('file-open:' + docPath);
  status('opened ' + docPath);
  e.target.value = '';
});

$('btn-open').onclick = () => $('file-input').click();

$('btn-save').onclick = () => {
  if (!docPath) {
    docPath = DOCS + '/drawing.svg';
    window.__doc_path = docPath;
  }
  if (docOpened) {
    runActions('document-save');
  } else {
    runActions('export-filename:' + docPath + ';export-do');
  }
  download(docPath.split('/').pop(), m.FS.readFile(docPath), 'image/svg+xml');
  flush();
  status('saved ' + docPath);
};

$('btn-export').onclick = () => {
  runActions('export-filename:' + DOCS + '/export.png;export-do');
  download('export.png', m.FS.readFile(DOCS + '/export.png'), 'image/png');
  flush();
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
