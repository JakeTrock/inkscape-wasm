# Leg E — Harness

Goal: one harness that serves three roles — dev loop instrument, browser
test rig, and the v1 demo shell. Kept deliberately small: a static page,
a loader script, and test tooling.

## Dev harness (`harness/`)

`harness/index.html` + `harness/loader.js`, served by `make serve`
(`python3 -m http.server` on a fixed port, no build step):

```
┌────────────────────────────────────────────────┐
│ toolbar: [Open SVG] [Save] [Export PNG] ▾status │
│ ┌────────────────────────────────────────────┐ │
│ │            broadway window container       │ │
│ │            (fills viewport)                │ │
│ └────────────────────────────────────────────┘ │
│ console: stdout/stderr from the module, errors │
│          with stack, boot stage indicator       │
└────────────────────────────────────────────────┘
```

- **Boot stages** shown as a checklist (module fetched → FS mounted →
  fonts cached → inkscape init → broadway connected) so a hang is
  immediately localizable. Stage transitions come from the module via a
  tiny `harness_log()` export.
- **Console panel**: `Module.print/printErr` captured; uncaught JS
  exceptions and emscripten `EXIT_RUNTIME` failures rendered with stack.
- **Open SVG**: file input → writes into `/home/web_user/` (IDBFS) →
  invokes Inkscape's `file-open` action through the bridge (same action
  mechanism T5 uses headless).
- **Save / Export PNG**: pulls the file out of IDBFS and offers a
  download blob. (In v1 this doubles as the file-dialog replacement;
  leg C patches Inkscape's dialog layer to route through these.)
- **Hard reload** button: wipes IDBFS and reboots the module (unsticks a
  wedged run without a manual browser reset).
- No frameworks, no bundler — plain ES modules + the emscripten glue.

## Test harness

- **Node rungs (T0, T1, T4, T5)**: `tests/tN/run.mjs` scripts — spawn
  `node` on emscripten-built binaries, assert on exit codes, output
  files, and golden diffs. No new dependencies beyond emsdk's node.
- **Browser rungs (T2, T3, T6, T7)**: Playwright + Chromium + pixelmatch
  (`tests/package.json`, the only npm install in the repo). A shared
  `tests/browser/spec-util.ts` handles: launch with fixed flags, serve
  `harness/` + build outputs on an ephemeral port, wait-for-boot-stage
  helper, screenshot + diff helpers.
- **T7 scripted session** drives the real GUI over Playwright's mouse
  API: select rectangle tool (toolbar click coordinates recorded from the
  T6 golden), drag on canvas, Save via harness toolbar, assert SVG
  contents, Export PNG, golden-compare.
- Everything long-running launches via `oc-bg`; `make check-N` prints the
  log path immediately and the verdict lands in the log + stamp.

## Exit conditions for the harness work

Done when: T7 passes end-to-end from `make check-7` on a clean checkout,
and a developer can go from `make serve` to drawing a shape in under a
minute of page load. No further polish (theming, PWA, shortcuts) in v1.
