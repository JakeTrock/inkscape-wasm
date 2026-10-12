# Leg A — Toolchain & Sysroot

Goal: an Emscripten cross-compilation environment and a sysroot containing
every Inkscape dependency, built from source, testable in Node, reproducible
via one command (`make deps`).

## Toolchain

- **Emscripten**: use the existing emsdk at `../toki/emsdk` (sibling repo
  dir). Activate via `source ../toki/emsdk/emsdk_env.sh` in every build
  script — never rely on a global `emcc`.
- Pin and record the version in `build/sysroot/manifest.txt` at T0. Upgrade
  only if a dependency requires it; record any upgrade the same way.
- **Flags common to every package** (set in `packages/common.sh`):
  ```
  -ffunction-sections -fdata-sections
  -fexceptions -frtti                # Inkscape needs both
  -sALLOW_MEMORY_GROWTH
  -sASYNCIFY                         # leg B: main-loop bridging
  -sMODULARIZE=1 -sEXPORT_ES6        # consumed by harness/loader
  ```
  Threads are off: no `-pthread`, no SharedArrayBuffer anywhere.
- `ccache` in front of every compiler invocation (64 cores available; it
  makes iteration rebuilds minutes instead of hours).
- `pkg-config` works against the sysroot via
  `PKG_CONFIG_PATH=$SYSROOT/lib/pkgconfig` and
  `PKG_CONFIG_SYSROOT_DIR=$SYSROOT`.

## Directory layout

```
Makefile               targets: deps, inkscape, check-N, serve, clean
packages/common.sh     sourced by every package script (flags, sysroot paths)
packages/<pkg>.sh      one per dependency: download, patch, configure, build, test
patches/<pkg>/*.patch  our diffs vs upstream
build/sysroot/         --prefix for every package (artifacts, gitignored)
build/logs/            oc-bg logs
src/                   extracted Inkscape 1.4.4 source (gitignored)
```

Every package script is idempotent and stamp-driven
(`build/stamps/<pkg>.ok`): rerunning `make deps` only rebuilds what changed.

## Dependency list & build order

Versions below are initial pins; adjust only when a build or test fails,
and record the final pin in `packages/<pkg>.sh` + `manifest.txt`.

| # | Package | Pin (initial) | Notes |
|---|---------|---------------|-------|
| 1 | zlib | 1.3.1 | |
| 2 | libpng | 1.6.45 | |
| 3 | freetype | 2.13.3 | |
| 4 | fontconfig | 2.16.0 | cache built at runtime, persisted to IDBFS (leg C) |
| 5 | pixman | 0.46.2 | |
| 6 | fribidi | 1.0.16 | |
| 7 | harfbuzz | 11.x latest | needs freetype integration off or on — decide by test |
| 8 | expat | 2.7.x | fontconfig dep |
| 9 | **cairo** | 1.18.2 | image + (broadway's) surface backends; no X/Qt |
| 10 | **glib** | 2.84.x | patches expected: main-loop/poll (leg B) |
| 11 | pango | 1.56.x | |
| 12 | gdk-pixbuf | 2.42.x | loaders: png, svg?, jpeg — keep png only |
| 13 | atk | 2.38.0 | GTK3 dep |
| 14 | **GTK3** | 3.24.x latest | **broadway backend only** — see below |
| 15 | libsigc++ | 2.12.x | |
| 16 | glibmm | 2.66.x | the `glibmm-2.4` ABI line gtkmm3 wants |
| 17 | cairomm | 1.14.x | `cairomm-1.0` line |
| 18 | pangomm | 2.48.x | `pangomm-2.48` for gtkmm3 |
| 19 | **gtkmm** | 3.24.x | |
| 20 | libxml2 | 2.13.x | |
| 21 | libxslt | 1.1.x | |
| 22 | gsl | 2.8 | |
| 23 | double-conversion | 3.3.x | |
| 24 | boost | 1.86+ | headers only subset Inkscape uses |
| 25 | **libgc** (Boehm) | 8.2.8+ | **top risk — see below** |
| 26 | potrace | 1.16 | optional; include if free |
| 27 | **lib2geom** | 1.4.x | from the Inkscape 1.4.4 release (matching submodule ref) |

Addendum (2026-10-12, from planning): glib requires **libffi** (GObject
closures). Build it immediately before glib (pin 3.4.7). WASM closure
support is a known hazard — it gets a dedicated T1 smoke test like libgc,
and if stock libffi fails, the known emscripten fork patches are the
fallback.

GTK3 configure essentials: `--enable-broadway-backend --disable-x11-backend
--disable-wayland-backend --disable-quartz-backend` plus the usual
`--disable-gtk-doc`, introspection off, demos/tests off. The `broadwayd`
sources themselves are compiled into our module (leg B), not built as a
separate binary.

## Boehm GC (risk #1) — decision ladder

Tested immediately at T1, before GTK or anything above it:

1. **Try libgc 8.2.8+ with** `--disable-threads`, host-stack scanning
   replaced by emscripten's stack bounds (`emscripten_stack_get_base/`,
   `__stack_base`/`__stack_end` exported symbols), configure
   `GC_no_dlopen=1`-style minimalism. If its own test suite passes in
   Node (allocation + collection of cyclic garbage), done.
2. **Custom mark roots**: register Inkscape's GC-visible structures as
   roots explicitly and disable stack scanning. More patching, still real
   collection.
3. **Stub GC (last resort)**: `GC_malloc` = `malloc`, `GC_register...` =
   no-ops, nothing freed. Leaks by design; acceptable for a demo harness.
   Documented in code as `shortcut: leaks memory, fine for single-document
   sessions; upgrade to real libgc before long-running use`.

Whatever rung we land on is recorded here and in `packages/libgc.sh`.

## Per-package testing (T1)

Each package script ends with its smoke test under Node:

- C libraries with test suites (glib, libxml2, lib2geom): build and run a
  curated subset of the suite via `emcc`-linked test binaries.
- Libraries without usable tests (atk, sigc++...): a tiny handwritten C
  program per package that exercises the API surface Inkscape uses, linked
  against the sysroot build, run in Node, assert-based.
- Pass = stamp written. `make check-1` re-runs all stamps' tests.

## Cost model

First full `make deps`: expect several hours on 64 cores, run via `oc-bg`.
Incremental (one package changed): minutes. Disk: expect 20–40 GB in
`build/` (2.3 TB free — fine).
