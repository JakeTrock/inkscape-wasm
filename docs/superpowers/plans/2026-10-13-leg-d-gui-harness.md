# Leg D/E — Inkscape GUI + Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot the full Inkscape GUI in a browser tab over the Leg-B bridge and prove it end-to-end — gates **T6** (window chrome + toolbox + canvas painted, Playwright-verified) and **T7** (rectangle drawn with a real canvas click-drag, saved, exported PNG pixel-compared) — plus the spec-05 dev harness (toolbar, boot stages, console) that doubles as the v1 demo shell.

**Architecture:** No new bridge machinery. The Leg-C module already contains the daemon and bridge (`libinkbridge.a`); it just never exports them and never yields from `main`. Two small Inkscape patches fix both: main registers + activates the GApplication but returns before `g_application_run`'s blocking loop (the page's rAF tick drives `g_main_context_iteration` via `_bridge_frame`, exactly the t2/t3 pattern), and an `EMSCRIPTEN_KEEPALIVE` `inkscape_run_actions()` gives JS a runtime entry into Inkscape's action system (same `parse_actions` + `activate_any_actions` path `--batch-process` uses). The harness page is one static HTML+JS pair staged next to the built module.

**Tech Stack:** existing emsdk module build (cmake relink only), plain ES modules + broadway.js (sed-swapped `BridgeSocket`), Playwright 1.64 + pixelmatch (both already installed under `tests/`).

## Grounding facts (verified against the real trees on 2026-10-13 — do not re-derive)

- Built module: `build/inkscape/bin/inkscape.{js,wasm}` (43 MB) + `inkscape.data` (42 MB), MODULARIZE=1, EXPORT_NAME=Module, EXIT_RUNTIME default 0, INITIAL_MEMORY 512 MB + ALLOW_MEMORY_GROWTH, EXPORTED_RUNTIME_METHODS=HEAPU8,callMain,FS. `main()` already sets GDK_BACKEND=broadway (unless caller overrides), FONTCONFIG_FILE, INKSCAPE_PROFILE_DIR=/home/web_user, XDG_DATA_DIRS (patch `broadway-env`).
- **`_bridge_frame` & co. are NOT exported** (grep of inkscape.js: 0 hits) — link flags lack `-sEXPORTED_FUNCTIONS`. `-sEXPORTED_FUNCTIONS` *replaces* the default list, so it must include `_main` (callMain), `_malloc`, `_free`.
- Main loop: `src/inkscape-main.cpp:245` — `auto ret = InkscapeApplication().gio_app()->run(argc, argv);`. glibmm 2.66 has `Gio::Application::register_application()` (giomm/application.h:866) and `activate()` (:898). `g_application_register` emits ::startup (→ GtkApplication's `gtk_init`), `g_application_activate` emits ::activate (→ `InkscapeApplication::on_activate` → `create_window`). Both calls already run inside `run()` on wasm today — T5 proved register/activate/quit headless; only the loop entry is new to skip.
- Welcome screen: prefs fixture (`showwelcome=0`) already staged into the FS by inkscape.sh (Leg C) — `on_activate` goes straight to `create_window`.
- Action entry point: `InkscapeApplication::parse_actions(const Glib::ustring&, action_vector_t&)` is **public** (inkscape-application.h:185); `activate_any_actions(...)` is file-static in inkscape-application.cpp; `InkscapeApplication::instance()` (public static, .cpp:576) returns the singleton. The interactive `shell()` member (.cpp:1420-1425) shows the exact wrap to use: `"active-window-start;" + input + ";active-window-end"` then parse + activate. `_gio_application`/`_active_window`/`_active_document` are private → the hook must be a member, not a free function.
- File actions (actions-file.cpp): `file-open:<path>`, `file-close`, `file-new` exist as gio-app actions; **`file-save`/`export-*` are ink-actions only** — reachable solely through the parse_actions path (why the hook is needed at all).
- Tool switch: `win:tool-switch('Rect')` exists (actions-tools.cpp) — fallback if the F4 accel misbehaves.
- Leg-C caveat to re-test: "with broadway, create_window blocks waiting for a client that headless tests never provide" — t2/t3 GTK apps created windows clientless in node, so this is suspected to have been the welcome-screen modal loop (now disabled by prefs). Task 1's node smoke answers it cheaply. Ordering constraint discovered while writing it: `_bridge_js_connect` **no-ops while `bserver == NULL`** (bridge.c), and the daemon only exists after `gtk_init` runs inside `callMain` — harness order is callMain → connect → rAF tick (t2 did connect-after-boot too). If create_window truly blocks clientless, that deadlocks; the fix is lazy daemon-init in `bridge_js_connect` — only if the smoke hangs.
- Session rule that shapes T7: **the model must never `read` images** — all screenshot assertions are textual facts (canvas geometry dumps, pixel-region counts via `page.evaluate`), exactly like `tests/t2/debug.mjs`. The spec's "toolbar click coordinates recorded from the T6 golden" is therefore replaced by **F4** (Inkscape's rect-tool accel, a real GUI keypress through broadway.js) — deviation recorded below.
- Broadway.js input: DOM events on its canvases → `sendInput` → `BridgeSocket.send` → pipe B; mouse down/move/up and key events all flow this way (t2 proved click). Playwright `page.mouse` + `page.keyboard` hit them.
- `begin_pkg inkscape` exits early on `build/stamps/inkscape.ok`; a relink also requires deleting `build/inkscape/bin/inkscape.{js,wasm}` (ninja can't see `-l` archive changes — Leg-C finding). `.data` only changes if the FS staging changes (it doesn't in this leg).

## Deviations from spec 04/05 (record in findings when done)

1. **Rect tool selected via F4 accel, not toolbar pixel-click** — text-only model can't read goldens to pick button coords; F4 is a real GUI keypress, deterministic, and self-checking (no `<rect>` in the saved doc ⇒ the gate fails anyway).
2. **T7 export "golden" is self-consistent**: native inkscape exports *the SVG this run saved* and pixelmatch compares the wasm export against it (threshold in `tests/manifest.json`). A committed golden of the drawn doc would also work but adds a regeneration step for zero extra coverage.
3. **Boot stages are JS-observable facts** (factory resolved, runtime ready, broadway connected + first bytes, first canvas, first pumped frame) — no C-side `harness_log()` export; every stage the spec lists is still displayed.
4. **IDBFS skipped in v1** — Open/Save/Export work against the in-memory FS with blob downloads to the host. Persistence across reloads is demo polish beyond the T7 exit condition. `shortcut: no persistence across reloads; add an IDBFS mount at /home/web_user/documents if the demo needs it.`
5. **Save on a never-opened document** opens Inkscape's own Save-As dialog (a broadway GTK dialog — it works, but is unscripted). The harness tracks the last-opened path; T7 always opens a fixture first, so `file-save` has a filename.

## Global Constraints (inherited)

- Repo root `/data/jake/reversing/inkscape`; emscripten only via `source packages/common.sh`.
- Patches in `patches/inkscape/`, reverse-dry-run guarded, generated from a pristine tree edit under /tmp/opencode (never in-place `build/src` edits).
- Long builds (>2 min) via `oc-bg <log> -- <cmd>`; stamps `build/stamps/check-{6,7}.ok`; commit after every task.
- Playwright browsers already cached; never `npm install` without `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`.

## File Structure

```
patches/inkscape/main-loop-yield-emscripten.patch   — register+activate, return before run()'s loop
patches/inkscape/action-hook-emscripten.patch       — InkscapeApplication::run_actions() + KEEPALIVE export
packages/inkscape.sh                                — 2 new patches + EXPORTED_FUNCTIONS in linker flags
tests/t6/boot-smoke.mjs                             — node GUI-boot smoke (Task 1)
harness/index.html, harness/loader.js               — spec-05 dev harness / demo shell
tests/lib/harness_stage.sh                          — stage module + harness page into build/harness/
tests/t6/run.sh, tests/t6/t6.spec.ts                — T6 gate
tests/t7/run.sh, tests/t7/t7.spec.ts                — T7 gate
tests/fixtures/t7-rect.svg                          — blank doc for the draw session
tests/manifest.json                                 — t7 pixelmatch threshold
Makefile                                            — check-6, check-7, serve
```

---

### Task 1: Yield from main + action hook + bridge exports (relink)

**Files:**
- Create: `patches/inkscape/main-loop-yield-emscripten.patch`,
  `patches/inkscape/action-hook-emscripten.patch`, `tests/t6/boot-smoke.mjs`
- Modify: `packages/inkscape.sh`

**Interfaces:**
- Produces (JS-visible on the module): `_main`, `_malloc`, `_free`,
  `_bridge_frame`, `_bridge_js_connect`, `_bridge_js_write`, `_bridge_js_poll`,
  `_bridge_js_poll_ptr`, `_inkscape_run_actions(const char *actions)`.
- Produces (C++, inkscape-internal): `InkscapeApplication::run_actions(const Glib::ustring&)` (emscripten only).

- [ ] **Step 1: Generate `main-loop-yield-emscripten.patch`**

  Pristine-tree edit of `src/inkscape-main.cpp` (the tree in
  `build/src/inkscape-1.4.4` is already patched — copy file to
  /tmp/opencode, revert by hand, or `git -C build/src/inkscape-1.4.4 diff`
  style; the existing patches applied there give the base state, so diff the
  *post-existing-patches* file against the *post-new-patch* file exactly like
  Leg C did). Replace line 245:

  ```cpp
      auto ret = InkscapeApplication().gio_app()->run(argc, argv);
  ```

  with:

  ```cpp
  #ifdef __EMSCRIPTEN__
      /* wasm: never enter g_application_run's blocking loop — the single JS
       * thread must return to the page, whose rAF tick drives the default
       * main context via bridge_frame(). register emits ::startup (gtk_init),
       * activate emits ::activate -> on_activate -> create_window. */
      InkscapeApplication app;
      app.gio_app()->register_application();
      app.gio_app()->activate();
      return 0;
  #else
      auto ret = InkscapeApplication().gio_app()->run(argc, argv);
  #endif
  ```

  (Keep the `_WIN32` block and `return ret;` under the `#else` — mind that
  `return ret` now needs to live in the non-emscripten path.)

- [ ] **Step 2: Generate `action-hook-emscripten.patch`**

  a. `src/inkscape-application.h` — public section, after `parse_actions`:

  ```cpp
  #ifdef __EMSCRIPTEN__
      /// Run an action string (e.g. "file-save") in the active window context.
      void run_actions(const Glib::ustring &input);
  #endif
  ```

  b. `src/inkscape-application.cpp` — near `shell()` (it shares the wrap logic):

  ```cpp
  #ifdef __EMSCRIPTEN__
  /* wasm: JS entry into the action system (harness toolbar / tests).
   * Same path as --batch-process, wrapped for the active window like shell(). */
  void InkscapeApplication::run_actions(const Glib::ustring &input)
  {
      Glib::ustring wrapped = "active-window-start;" + input + ";active-window-end";
      action_vector_t action_vector;
      parse_actions(wrapped, action_vector);
      activate_any_actions(action_vector, _gio_application, _active_window, _active_document);
  }

  extern "C" __attribute__((used)) void
  inkscape_run_actions(const char *input)
  {
      auto *app = InkscapeApplication::instance();
      if (app) app->run_actions(input);
  }
  #endif
  ```

  (`__attribute__((used))` keeps the export without touching
  EXPORTED_FUNCTIONS; verify with `grep -c _inkscape_run_actions` on the
  relinked inkscape.js.)

- [ ] **Step 3: `packages/inkscape.sh` changes**

  a. Add both patches to the patch loop.
  b. Append to `CMAKE_EXE_LINKER_FLAGS`:

  ```
  -sEXPORTED_FUNCTIONS=_main,_malloc,_free,_bridge_frame,_bridge_js_connect,_bridge_js_write,_bridge_js_poll,_bridge_js_poll_ptr
  ```

- [ ] **Step 4: Relink (oc-bg — cmake reconfigure + link, ccache makes it minutes)**

  ```bash
  rm build/stamps/inkscape.ok build/inkscape/bin/inkscape.{js,wasm}
  oc-bg build/logs/inkscape-gui -- make pkg-inkscape
  ```

  Verify in the log: build OK; `grep -c "_bridge_frame\|_inkscape_run_actions" build/inkscape/bin/inkscape.js` ≥ 2. Also rerun `make check-5` (cached stamp is fine — only if flags changed the module, drop the stamp and rerun: headless boot must not regress).

- [ ] **Step 5: Node GUI-boot smoke (`tests/t6/boot-smoke.mjs`)**

  ```js
  // Boots inkscape.wasm in GUI mode (broadway) in node: callMain must RETURN,
  // bridge_frame must pump, the daemon must produce browser-bound bytes.
  import { join, dirname } from 'node:path';
  import { pathToFileURL } from 'node:url';

  const modulePath = process.argv[2] || 'build/inkscape/bin/inkscape.js';
  const factory = (await import(pathToFileURL(modulePath))).default;
  const m = await factory({
    noInitialRun: true,
    locateFile: f => join(dirname(modulePath), f),
    print: t => console.log(t), printErr: t => console.error(t),
  });

  m._bridge_js_connect();          // browser client exists from t=0
  m.callMain([]);                  // must return (main-loop-yield patch)
  console.log('boot-smoke: callMain returned');

  let bytes = 0, frames = 0;
  for (let i = 0; i < 300; i++) {  // ~5s of "rAF" at 60fps
    m._bridge_frame();             // one nonblocking iteration
    bytes += Math.max(0, m._bridge_js_poll());
    frames++;
  }
  console.log(`boot-smoke: ${frames} iterations, ${bytes} daemon->browser bytes`);
  if (bytes <= 0) { console.error('boot-smoke FAIL: daemon never sent bytes — window was never created/drawn'); process.exit(1); }
  console.log('boot-smoke PASS');
  process.exit(0);
  ```

  Run: `node tests/t6/boot-smoke.mjs`. If it hangs inside `callMain` → the
  Leg-C "blocks waiting for a client" finding was real: debug with the CDP
  cpu-prof trick from Leg C findings, fix at the specific GDK call (likely a
  round-trip that needs the browser input source to dispatch — the daemon
  processes pipe-B writes inside `_bridge_js_write`, so also try pumping
  `_bridge_js_poll` + re-`_bridge_frame` from a `setInterval` *before*
  concluding; JS is single-threaded, a blocked callMain can't be pumped
  around). If it aborts, read the console stderr — icon/font issues were
  solved in Leg C; new aborts get findings entries.

- [ ] **Step 6: Commit**

  ```bash
  git add -A && git commit -m "leg D: main-loop yield + JS action hook + bridge exports — inkscape GUI boots headless-in-node (boot-smoke PASS)"
  ```

---

### Task 2: Dev harness page (spec 05) + staging + make serve

**Files:**
- Create: `harness/index.html`, `harness/loader.js`, `tests/lib/harness_stage.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: module exports from Task 1; `bridge.js` (`BridgeSocket`, `pumpDaemon`);
  broadway.js (sed-swapped, as `tests/lib/wasm_harness.sh` does).
- Produces: `build/harness/` servable page; `make serve` (http.server 8824 on
  `build/`); page globals for tests: `window.__boot` (stage flags), each stage
  lights a DOM node with `id="stage-<n>"` + `data-state="ok"`.

- [ ] **Step 1: `harness/index.html`** — spec-05 layout, no frameworks:

```
toolbar: [Open SVG] [Save] [Export PNG] [Hard reload] | status line
broadway container (fills viewport)
console panel (fixed height, Module.print/printErr + window.onerror, autoscroll)
boot-stage checklist: module fetched / runtime ready / broadway connected / window up / first frame
```

  Scripts (plain, in order, into `build/harness/` by the stager):
  `inkscape.js` (as `Module` factory — t2 pattern), `rawinflate.min.js`,
  `bridge.js`, `broadway.js` (sed'd). Body script imports `./loader.js`
  (type=module).

- [ ] **Step 2: `harness/loader.js`** — the whole harness brain (~120 lines):

  - `Module({ noInitialRun: true, locateFile, print, printErr })` → stage 1-2.
  - `window.__bridge_mod = m`; `connect()` (broadway.js → `BridgeSocket`) →
    stage 3 on first `pumpDaemon` bytes.
  - `m.callMain([])`; rAF tick: `m._bridge_frame(); pumpDaemon();` → stage 4
    when `document.querySelector('canvas')` appears (poll inside the tick),
    stage 5 after the first tick that follows.
  - Toolbar:
    - **Open**: `<input type=file>` → `m.FS.writeFile('/home/web_user/' + name, bytes)`
      → `m._inkscape_run_actions('file-open:/home/web_user/' + name)`; track
      `window.__doc_path`.
    - **Save**: `_inkscape_run_actions('file-save')`, then read
      `window.__doc_path` via `m.FS.readFile` → download blob (type image/svg+xml).
    - **Export PNG**: `_inkscape_run_actions('export-filename:/home/web_user/export.png;export-do')`
      → read file → download blob.
    - **Hard reload**: `location.reload()`.
  - Status line: current stage text + last console line. Errors from
    `window.onerror` render with stack in the console panel (spec 05).

- [ ] **Step 3: `tests/lib/harness_stage.sh`**

  ```bash
  # stage_harness — build/harness/ gets: module trio, bridge.js, broadway.js
  # (sed'd), rawinflate, harness/*, t7 fixture NOT included (opened via file input).
  stage_harness() {
    local out="$BUILD/harness"; mkdir -p "$out"
    cp "$BUILD/inkscape/bin/inkscape.js" "$BUILD/inkscape/bin/inkscape.data" \
       "$BUILD/inkscape/bin/inkscape.wasm" "$out/"
    cp "$ROOT/bridge/bridge.js" "$out/"
    cp "$BUILD/test/rawinflate.min.js" "$out/"   # location per wasm_harness.sh
    sed -e 's/ws = new WebSocket(loc, "broadway");/ws = new BridgeSocket();/' \
        "$SRC/gtk3/gdk/broadway/broadway.js" > "$out/broadway.js"
    grep -q "new BridgeSocket()" "$out/broadway.js"
    cp "$ROOT"/harness/* "$out/"
  }
  ```

  (Check where `rawinflate.min.js` actually lives — `wasm_harness.sh` copies
  it into every harness dir; reuse the same source path.)

- [ ] **Step 4: Makefile** — `check-6 check-7 serve` phony targets;
  `serve: ; python3 -m http.server 8824 --directory build`.

- [ ] **Step 5: Manual smoke (foreground, quick)** — `make serve` in
  background, `node tests/t2/debug.mjs`-style textual probe or just
  `curl -s localhost:8824/harness/index.html | head` (page loads; full browser
  check is Task 3's job). Commit:

  ```bash
  git add -A && git commit -m "leg D/E: dev harness page — toolbar, boot stages, console; staging + make serve"
  ```

---

### Task 3: T6 gate — GUI painted in a browser tab (make check-6)

**Files:**
- Create: `tests/t6/run.sh`, `tests/t6/t6.spec.ts`
- Modify: `Makefile` (target), `tests/playwright.config.ts` only if timeout needs raising (96 MB fetch on localhost — set test timeout 120s)

**Passes when:** broadway canvases exist, a large canvas region is painted
(ink window > 800 px wide), the toolbox column and the white drawing area are
both detectable as pixel statistics, and a screenshot lands in
`build/t6/t6-shot.png`. Canvas geometry dumped as TEXT to
`build/t6/t6-geom.json` (Task 4 consumes it).

- [ ] **Step 1: `tests/t6/t6.spec.ts`** (fixed viewport 1280×800, per spec 04):

  ```ts
  test('T6: inkscape GUI boots — chrome, toolbox, canvas', async ({ page }) => {
    await page.goto('/harness/index.html');
    // boot stages light up in order; window up = canvas exists
    await page.waitForSelector('#stage-runtime-ready[data-state=ok]', { timeout: 30000 });
    await page.waitForSelector('canvas', { timeout: 60000 });
    await page.waitForSelector('#stage-first-frame[data-state=ok]', { timeout: 30000 });
    await page.waitForTimeout(2000); // settle a few frames

    const facts = await page.evaluate(() => {
      const out = { canvases: [], tallies: [] };
      for (const c of document.querySelectorAll('canvas')) {
        const r = c.getBoundingClientRect();
        out.canvases.push({ x: r.x, y: r.y, w: r.width, h: r.height,
                            px: c.width, py: c.height });
      }
      // pixel tallies over the biggest canvas: toolbox column vs canvas body
      const big = [...document.querySelectorAll('canvas')]
        .sort((a, b) => b.width * b.height - a.width * a.height)[0];
      const ctx = big.getContext('2d');
      const d = ctx.getImageData(0, 0, big.width, big.height).data;
      const dark = (x, y) => { const i = (y * big.width + x) * 4;
        return d[i] < 128 && d[i+1] < 128 && d[i+2] < 128; };
      let toolDark = 0, bodyLight = 0;
      for (let y = 0; y < big.height; y += 4) {
        for (let x = 0; x < 40; x += 2) if (dark(x, y)) toolDark++;
        for (let x = 60; x < Math.min(600, big.width); x += 8)
          { const i = (y * big.width + x) * 4;
            if (d[i] > 235 && d[i+1] > 235 && d[i+2] > 235) bodyLight++; }
      }
      out.tallies = [{ toolDark, bodyLight }];
      return out;
    });
    // console output includes the tallies for the log (text evidence, no image reads)
    console.log('T6 facts:', JSON.stringify(facts));

    const big = facts.canvases.reduce((a, b) => a.w * a.h > b.w * b.h ? a : b);
    expect(big.w).toBeGreaterThan(800);
    expect(big.h).toBeGreaterThan(500);
    expect(facts.tallies[0].toolDark).toBeGreaterThan(30);   // left icon bar painted
    expect(facts.tallies[0].bodyLight).toBeGreaterThan(2000); // white drawing area

    await page.screenshot({ path: '../build/t6/t6-shot.png' });
  });
  ```

  (Numbers are first-guess thresholds — tune once against the real dump,
  recording final values in the spec file comment. If the "biggest canvas"
  isn't the ink window (broadway makes one canvas per surface), adjust the
  picker to the largest *content* canvas and note it.)

- [ ] **Step 2: `tests/t6/run.sh`** — t2 pattern: stamp check, source
  common.sh + harness_stage.sh, `stage_harness`, ensure node_modules,
  `npx playwright test t6/t6.spec.ts`, stamp `check-6.ok`. Also dump
  `build/t6/t6-geom.json` from inside the spec (write facts there via
  `fs.writeFileSync` in the test) for Task 4.

- [ ] **Step 3: Run `make check-6`** (foreground; page load is the slow part,
  still < 2 min). Debug with the t2/t3 `debug.mjs` probe pattern (textual
  facts only). On hang: check which boot stage never lit — module (fetch),
  runtime (wasm compile), broadway (connect), window (canvas), frame — each
  maps to a distinct subsystem.

- [ ] **Step 4: Commit**

  ```bash
  git add -A && git commit -m "leg D: T6 gate green — inkscape GUI painted in browser (check-6)"
  ```

---

### Task 4: T7 gate — draw, save, export (make check-7)

**Files:**
- Create: `tests/fixtures/t7-rect.svg` (800×600 blank document),
  `tests/t7/run.sh`, `tests/t7/t7.spec.ts`
- Modify: `tests/manifest.json` (`"t7": 0.5`), `Makefile`

- [ ] **Step 1: fixture** — minimal valid svg: `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600" viewBox="0 0 800 600"><rect width="800" height="600" fill="#ffffff"/></svg>`.

- [ ] **Step 2: `tests/t7/t7.spec.ts`** — scripted session on the same page:

  1. Boot + stages (shared helper or copy from t6 — 10 lines, not worth a
     shared module yet).
  2. **Open**: `setInputFiles` on the harness file input with
     `tests/fixtures/t7-rect.svg` → wait for `__doc_path` set + 1s.
  3. **Rect tool**: `page.keyboard.press('F4')` (fallback under a `test.skip`:
     `page.evaluate` → `_inkscape_run_actions("tool-switch('Rect')")`).
  4. **Draw**: canvas coords from `build/t6/t6-geom.json` + fixed offsets
     (toolbox ~40 px, ruler ~25 px margins):
     `page.mouse.move(cx, cy); down(); move(cx+200, cy+150, {steps: 10}); up();`
     then 1s of frames.
  5. **Save**: click `#btn-save` → wait 1s → `page.evaluate(() =>
     __bridge_mod.FS.readFile(__doc_path))` → host-write via
     `fs.writeFileSync('build/t7/t7-saved.svg')`.
  6. **Assert SVG**: contains `<rect`; parse x/y/width/height attrs; expect
     width ∈ [80, 350] and height ∈ [60, 300] for a 200×150 drag (zoom may
     scale; loosen once against reality and record).
  7. **Export PNG**: click `#btn-export` → wait → read
     `/home/web_user/export.png` → host-write `build/t7/t7-wasm.png`.
  8. Screenshot `build/t7/t7-shot.png`.

- [ ] **Step 3: `tests/t7/run.sh`** — playwright spec, then the native leg +
  compare (mirrors t5/run.sh):

  ```bash
  INK_NATIVE="$BUILD/native/inkscape/bin/inkscape"
  "$INK_NATIVE" --batch-process --actions="file-open:$PWD/build/t7/t7-saved.svg;export-filename:$PWD/build/t7/t7-native.png;export-do;file-close" \
    || exit 1
  node tests/t5/compare.mjs "$BUILD/t7/t7-wasm.png" "$BUILD/t7/t7-native.png" \
    "$(node -p "require('./tests/manifest')['t7']")"
  ```

  (Set `INKSCAPE_PROFILE_DIR` for the native run to the same fixture prefs —
  copy the t5 golden-gen invocation exactly; check `tests/golden/gen.sh` for
  the established env and reuse it.)

- [ ] **Step 4: Run `make check-7`** — expect the fiddliest gate: if the drag
  produces no rect, dump `document.elementFromPoint` at the drag origin and
  the canvas stack order (broadway overlays canvases — the top one must
  receive the events; t2's click worked, so trust the pattern and check
  coordinates first). If the tool didn't switch, the F4 keypress may need the
  canvas focused (`page.click` on the canvas first) — or use the fallback.

- [ ] **Step 5: Commit**

  ```bash
  git add -A && git commit -m "leg E: T7 gate green — draw rect via canvas drag, save, export pixel-matches native (check-7)"
  ```

---

### Task 5: Wrap-up — findings, roadmap, exit conditions

- [ ] `docs/findings.md`: Leg D/E section — gate results, the deviations
  above, any new wasm quirks found (there will be some).
- [ ] Roadmap table: plan 4 status → done, gates column green.
- [ ] Exit check per spec 05: `make check-6 check-7` from clean stamps, and
  `make serve` → draw a shape in under a minute of page load (the T7 spec
  *is* this check, scripted).
- [ ] Commit: `leg D/E: findings + roadmap — port complete, T6/T7 green`.
