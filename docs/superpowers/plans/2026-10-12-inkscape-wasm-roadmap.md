# Inkscape WASM Port — Implementation Roadmap

The spec (`../specs/2026-10-12-inkscape-wasm/`) is executed as **four
gated plans**. Each plan produces working, testable software and ends at
a testing-ladder gate (spec leg D). A plan is written in full only when
its gate opens — later plans depend on discoveries (patches, versions,
libgc/libffi rungs) made by earlier ones, so writing them earlier would
produce fabricated detail.

| # | Plan | Gate in | Status | Produces |
|---|------|---------|--------|----------|
| 1 | [2026-10-12-leg-a-toolchain-sysroot.md](2026-10-12-leg-a-toolchain-sysroot.md) | T0, T1 | **this repo, ready to execute** | emsdk-verified sysroot with all ~28 deps, per-package Node smoke tests, libgc + libffi decisions |
| 2 | Leg B — Broadway bridge (written after T1) | T2, T3 | **done — gates green (2026-10-13)**, see [2026-10-13-leg-b-broadway-bridge.md](2026-10-13-leg-b-broadway-bridge.md) | in-memory byte-pipe bridge, patched broadway.js, GTK + gtkmm hello worlds painting in a browser tab |
| 3 | Leg C — Inkscape headless (written after T2) | T4, T5 | **done — gates green (2026-10-13)**, see [2026-10-13-leg-c-inkscape-headless.md](2026-10-13-leg-c-inkscape-headless.md) | lib2geom tests green; `inkscape.wasm` headless in Node, golden-compared PNG export — 4/5 fixtures pixel-identical, text 1.79% (AA) |
| 4 | Leg D/E — GUI + harness (written after T5) | T6, T7 | **ready to execute** — see [2026-10-13-leg-d-gui-harness.md](2026-10-13-leg-d-gui-harness.md) | full GUI in the harness page; Playwright draw-rect → save SVG → export PNG acceptance |

Failure of a gate triggers the spec's kill criteria and salvage path
(spec `00-overview.md`, risk register). Gate results are recorded in
`docs/findings.md`.
