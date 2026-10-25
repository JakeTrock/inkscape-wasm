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
// Coalesce high-frequency mousemove events to at most one per rAF tick so
// GDK_PRIORITY_EVENTS (0) never starves GDK_PRIORITY_REDRAW (120) / Canvas idle (200),
// and accumulate wheel deltas so trackpads/wheels don't fire excessive scroll steps.
let pendingMove = null;
let wheelAccum = 0;
let lastWheelTime = 0;
const origMouseMove = window.onMouseMove;
const origMouseWheel = window.onMouseWheel;
const flushMove = () => {
  if (pendingMove) {
    const ev = pendingMove;
    pendingMove = null;
    origMouseMove(ev);
  }
};
window.onMouseMove = ev => { pendingMove = ev; };
window.onMouseWheel = ev => {
  flushMove();
  const now = performance.now();
  if (now - lastWheelTime > 180) wheelAccum = 0;
  lastWheelTime = now;
  const raw = ev.wheelDelta !== undefined ? -ev.wheelDelta
            : (ev.deltaY !== undefined ? ev.deltaY * 3 : (ev.detail || 0) * 40);
  wheelAccum += raw;
  if (Math.abs(wheelAccum) < 120) {
    if (ev.preventDefault) ev.preventDefault();
    if (ev.stopPropagation) ev.stopPropagation();
    return false;
  }
  const sign = wheelAccum > 0 ? 1 : -1;
  wheelAccum -= sign * 120;
  if (Math.abs(wheelAccum) > 120) wheelAccum = sign * 60;
  return origMouseWheel(ev);
};
for (const fn of ['onMouseDown', 'onMouseUp', 'onMouseOver', 'onMouseOut']) {
  const orig = window[fn];
  window[fn] = function(ev) { flushMove(); return orig.apply(this, arguments); };
}
window.__boot.broadway = true; setStage('broadway');

const tick = () => {
  flushMove();
  m._bridge_frame();       // drains ready main-loop work within 10ms budget
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
let syncChain = fsLoaded;
const flush = () => {
  syncChain = syncChain.then(() => new Promise(res => m.FS.syncfs(false, res)));
  window.__fs_flushed = syncChain;
};
fsLoaded.then(() => {
  // exactly one persisted svg -> resume the last session's document
  const svgs = m.FS.readdir(DOCS).filter(f => f.endsWith('.svg'));
  if (svgs.length === 1) { docPath = DOCS + '/' + svgs[0]; window.__doc_path = docPath; }
});

async function normalizeImageFile(f) {
  const name = f.name || 'image.png';
  if (/\.(svg|png|jpe?g)$/i.test(name)) {
    return { name, bytes: new Uint8Array(await f.arrayBuffer()) };
  }
  if ((f.type && f.type.startsWith('image/')) || /\.(webp|gif|bmp|avif|ico)$/i.test(name)) {
    try {
      const bmp = await createImageBitmap(f);
      const c = document.createElement('canvas');
      c.width = bmp.width;
      c.height = bmp.height;
      c.getContext('2d').drawImage(bmp, 0, 0);
      const blob = await new Promise(res => c.toBlob(res, 'image/png'));
      const pngName = name.replace(/\.[^.]+$/, '') + '.png';
      return { name: pngName, bytes: new Uint8Array(await blob.arrayBuffer()) };
    } catch (_) {}
  }
  return { name, bytes: new Uint8Array(await f.arrayBuffer()) };
}

async function handleIncomingFile(f, mode) {
  const { name, bytes } = await normalizeImageFile(f);
  await fsLoaded;
  const targetPath = DOCS + '/' + name;
  m.FS.writeFile(targetPath, bytes);
  flush();
  const isSvg = /\.svg$/i.test(name);
  if (mode === 'import' || !isSvg) {
    runActions('file-import:' + targetPath);
    status('imported ' + targetPath);
  } else {
    docPath = targetPath;
    docOpened = true;
    window.__doc_path = docPath;
    runActions('file-open:' + targetPath);
    status('opened ' + targetPath);
  }
}

$('file-input').addEventListener('change', async e => {
  const files = [...(e.target.files || [])];
  const mode = window.__file_input_mode || 'open';
  window.__file_input_mode = 'open';
  for (const f of files) {
    await handleIncomingFile(f, mode);
  }
  e.target.value = '';
});

// Full-screen file drop zone: dragging an image/SVG onto the window imports it
// into the current document at the drop position instead of navigating the tab.
for (const evt of ['dragenter', 'dragover']) {
  window.addEventListener(evt, e => {
    e.preventDefault();
    e.stopPropagation();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
  }, true);
}
window.addEventListener('drop', async e => {
  e.preventDefault();
  e.stopPropagation();
  const files = [...(e.dataTransfer?.files || [])];
  if (!files.length) return;
  try {
    origMouseMove(e);
    m._bridge_frame();
  } catch (_) {}
  for (const f of files) {
    await handleIncomingFile(f, 'import');
  }
}, true);

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
    download(docPath.split('/').pop(), m.FS.readFile(docPath), 'image/svg+xml');
    flush();
    status('saved ' + docPath);
  }
};

$('btn-export').onclick = () => {
  runActions('export-filename:' + DOCS + '/export.png;export-do');
  download('export.png', m.FS.readFile(DOCS + '/export.png'), 'image/png');
  flush();
  status('exported export.png');
};

$('btn-reload').onclick = () => location.reload();

window.__on_wasm_save = path => {
  docPath = path;
  docOpened = true;
  window.__doc_path = path;
  try {
    download(path.split('/').pop(), m.FS.readFile(path), 'image/svg+xml');
  } catch (_) {}
  flush();
  status('saved ' + path);
};

window.__on_wasm_export = path => {
  try {
    const mime = path.endsWith('.svg') ? 'image/svg+xml' : 'image/png';
    download(path.split('/').pop(), m.FS.readFile(path), mime);
  } catch (_) {}
  flush();
  status('exported ' + path);
};

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
