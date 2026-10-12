# Leg C — Building Inkscape 1.4.4 for WASM

Goal: compile Inkscape against the Leg-A sysroot with every
browser-hostile feature disabled, package its runtime data, and get the
result to run headless in Node (T5) and then in the browser via Leg B
(T6–T7).

## Source

- Tarball: Inkscape 1.4.4 release from inkscape.org / GitLab
  (`INKSCAPE_1_4_4` tag), extracted to `src/inkscape-1.4.4/` (gitignored;
  download automated in `packages/inkscape.sh`).
- lib2geom comes from the matching release ref (its submodule pointer) —
  built separately in Leg A so its test suite can gate at T4.

## CMake configuration

```
-DCMAKE_TOOLCHAIN_FILE=emscripten-cmake-toolchain  (emscripten's)
-DCMAKE_PREFIX_PATH=$SYSROOT
-DBUILD_TESTING=OFF
-DWITH_DBUS=OFF          -DWITH_GSPELL=OFF
-DWITH_GTKMM_3_0=ON      (the GTK3 line; there is no other option in 1.4.x)
-DWITH_LIBPOPPLER=OFF    -DWITH_LIBWPG=OFF
-DWITH_IMAGE_MAGICK=OFF  -DWITH_LIBCDR=OFF -DWITH_VISIO=OFF
-DWITH_GTK_SOURCE_VIEW=OFF  (if the option exists in 1.4.4; else patch out)
-DWITH_LIBSOUP=OFF       -DWITH_ASPELL=OFF
-DWITH_INTERNAL_2GEOM=OFF   (use sysroot lib2geom)
-DENABLE_NLS=OFF
```

Exact flag names verified against `CMakeLists.txt` / `cmacheck` at build
time — the list above is the intent: **GUI + SVG engine + PNG export,
nothing else**. Any CMake option that pulls in a browser-hostile
dependency (process spawning, network clients, dlopen'd loaders) is OFF.

## Expected source patches (`patches/inkscape/`)

Each is a real patch file; this list is the anticipated set, refined
during T5:

1. **`fork`/`exec`/`system` removal** — crash handler (`Inkscape crash`
   handler spawns gdb), "open containing folder", browser-launch,
  `--shell`-mode subprocess bits. Stubbed to no-ops with one-line log
   messages.
2. **File dialogs** — native `GtkFileChooser` must be redirected: v1 uses
   a harness-provided JS file picker (leg E). Patch point: Inkscape's
   dialog abstraction, not GTK internals.
3. **Paths** — `INKSCAPE_UIDIR`, `INKSCAPE_ICONDIR` etc. must resolve to
   our mounted FS paths (`/inkscape/share/...`). Handled via CMake
   defines + a small `paths.cpp` patch if needed.
4. **Boehm GC** — depends on the Leg-A rung chosen for libgc; if the stub
   GC is used, Inkscape's `GC::General::alloc` wrappers need zero
   changes (they call libgc's API, which the stub implements).
5. **Fontconfig/env** — fontconfig config path patched to `/fonts/`
   (mounted, see below).

## Filesystem & data packaging

Two emscripten FS layers:

- **`/inkscape`** — read-only preload (`tools/filepackager`): the
  `share/` tree Inkscape needs — `ui/*.glade`, `icons/`, `keys/`,
  `paint/`, `examples`, extensions' non-Python bits, `themes`. Expect
  30–80 MB. Shipped as `inkscape.data`.
- **`/fonts`** — read-only preload: DejaVu Sans/Serif/Mono + Liberation
  families (metric-compatible fallbacks users expect in SVGs), plus a
  patched minimal `fonts.conf` pointing only at `/fonts`.
- **`/home/web_user`** — `IDBFS` mount, persisted across sessions: user
  documents, Inkscape preferences (`~/.config/inkscape`), fontconfig
  cache (built on first boot inside the module, then cached).

## Runtime configuration

- `GDK_BACKEND=broadway` set in-process before GTK init (patch or env).
- `GSK_RENDERER` n/a (GTK3); Cairo's broadway surface does the drawing.
- Display: the single Inkscape window is created maximized; the harness
  page's broadway container fills the viewport.
- Memory: start with `INITIAL_MEMORY=1GB`, `ALLOW_MEMORY_GROWTH` on.

## T5 — headless gate before the GUI

Before any browser involvement, the built module must pass in Node:

```
inkscape.wasm --actions="file-open:tests/golden/basic.svg; export-filename:/tmp/out.png; export-do; file-close"
```

- Input: a small SVG exercising shapes, text, paths, gradients.
- Output PNG compared (pixelmatch, leg D tolerances) against the same
  export produced by a **native** Inkscape 1.4.4 build (`make
  native-inkscape` target builds it against system libs — also our
  golden-generation tool).
- This rung surfaces engine-level blockers (GC, file I/O, locale,
  exceptions) where debugging is easy, before GUI pain starts.

## Build cost

Full Inkscape wasm build after deps: expect 30–60 min on 64 cores under
`oc-bg`. Link step produces `inkscape.{js,wasm}` + `inkscape.data`;
expected module size 150–400 MB — accepted for v1 (risk #4).
