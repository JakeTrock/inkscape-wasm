# Inkscape → WebAssembly: Design Overview

Date: 2026-10-12
Status: approved (pending spec review)
Repo root: `/data/jake/reversing/inkscape`

## Goal

Compile **Inkscape 1.4.4** (full GUI) to WebAssembly so it runs entirely
client-side in a browser tab, via GTK3's **Broadway** HTML5 backend.
No server-side streaming — the whole application is a `.wasm` module.

## Decisions (from scoping session)

| Decision | Choice |
|---|---|
| End product | Full GUI in browser, everything client-side |
| Route | GTK3 Broadway backend compiled into the WASM module |
| Version | Inkscape 1.4.4 (latest stable, GTK3/gtkmm3 era) |
| v1 acceptance | Window opens, canvas responds, draw a rectangle, save SVG, export PNG |
| Threading | Single-threaded (no pthreads, no SharedArrayBuffer) |
| Long builds | Run under `oc-bg`, logs under `build/logs/` |

## Why this is research-grade

No documented successful GTK3+Broadway fully-in-WASM port exists (checked
2026-10-12). Standard Broadway assumes a process boundary:

```
GTK app (GDK broadway backend) ──unix socket──> broadwayd daemon ──WebSocket──> broadway.js (browser)
```

A browser tab has no sockets and no daemon. Our port eliminates the
process/socket boundary: `broadwayd`'s relay logic is compiled into the
module and both sides of its socket boundary are patched to an in-memory
byte pipe exposed to the page. This bridge is the novel part of the port.

## Architecture

```
Browser tab
├── harness/index.html   loader page: glue JS + inkscape.wasm + inkscape.data
├── broadway.js          GTK's browser client, patched: WebSocket → byte pipe
└── inkscape.wasm        Inkscape 1.4.4 + gtkmm3 stack + broadwayd relay
    ├── GDK Broadway backend ──(in-memory byte pipe)── broadwayd relay ──(same pipe)── broadway.js
    ├── GLib main loop, driven by requestAnimationFrame (Asyncify around g_poll)
    ├── IDBFS filesystem: share/ data preloaded, user files + fonts persisted
    └── single-threaded; Asyncify where blocking is unavoidable
```

## Legs of the plan

Each leg has its own design doc:

| Leg | Doc | Covers |
|---|---|---|
| A. Toolchain & sysroot | [01-toolchain-sysroot.md](01-toolchain-sysroot.md) | Emscripten setup, ~25 dependency packages, build system, Boehm GC |
| B. Broadway bridge | [02-broadway-bridge.md](02-broadway-bridge.md) | In-memory transport, broadway.js patch, GLib main-loop bridging |
| C. Inkscape build | [03-inkscape-build.md](03-inkscape-build.md) | Source, CMake flags, source patches, filesystem, fonts |
| D. Testing ladder | [04-testing-ladder.md](04-testing-ladder.md) | T0–T7 rungs, kill criteria, golden-image testing, salvage path |
| E. Harness | [05-harness.md](05-harness.md) | Dev loader page + test harness (Node, Playwright) |

## Risk register (ranked)

| # | Risk | Impact | Mitigation | Where tested |
|---|---|---|---|---|
| 1 | **Boehm GC in WASM** — libgc scans the native stack; WASM hides it. Inkscape's SVG DOM relies on it | Port-blocking | (a) libgc Emscripten-friendly config; (b) custom roots via emscripten hooks; (c) leak-tolerant stub (`GC_malloc=malloc`, never free) — documented `shortcut:` | T1, before anything expensive |
| 2 | **GLib main loop ↔ browser loop** — glib polls fds, browser can't block | Port-blocking | Asyncify allowlist around `g_poll`, woken by rAF; fallback: custom GSource | T2 (the make-or-break spike) |
| 3 | Broadway bridge patch complexity | High | Both patched sides are small, well-defined C seams (GSocket send/recv in GDK; accept/relay in broadwayd) | T2 |
| 4 | WASM module size (likely 150–400 MB) | Low | v1 is local-only; ignored | — |
| 5 | Font rendering / input focus / clipboard | Papercuts | Ship DejaVu+Liberation font bundle; harness substitutes for dialogs | T6–T7 |

**Salvage path:** the ladder is ordered so that if T2 (GUI in browser)
proves unsolvable, we still exit with T5 — a headless WASM Inkscape export
engine (SVG → PNG in Node/browser), which is independently useful.

## Explicitly cut from v1

Printing, dbus, Python extensions, PDF import (poppler), spell-check
(gspell), XML editor source view (gtksourceview), libsoup integration,
ImageMagick, browser-launch, IME, pthreads. Bitmap tracing (potrace)
included only if it builds without extra effort.

## Conventions

- All long-running commands (dependency builds, Inkscape builds, full test
  suites) launch via `oc-bg <log> -- <cmd>` and are checked on later turns.
- Every patch against upstream lives in `patches/<pkg>/` as a `.patch`
  file, applied by the package build script — never edit extracted source
  in place.
- Exact dependency versions are pinned in `packages/*.sh` and recorded in
  `build/sysroot/manifest.txt` on first successful build.
