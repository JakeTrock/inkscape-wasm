# Leg C — Inkscape Headless Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Inkscape 1.4.4 against the Leg-A sysroot, pass gate **T4** (lib2geom's own test suite green in Node) and gate **T5** (`inkscape.wasm` opens an SVG and exports a PNG headless in Node, golden-compared via pixelmatch against a native 1.4.4 build).

**Architecture:** No new bridge work — T5 runs the *same* module Leg B proved out (GDK-broadway over the in-module daemon), just driven from Node with no browser client attached. The leg is mostly build engineering: three small missing sysroot packages, googletest for 2geom's suite, the Inkscape CMake configure with every browser-hostile feature OFF, a packaged `share/` + fonts preload, and a native-build golden pipeline.

**Tech Stack:** Emscripten 6.0.6 (existing emsdk), CMake+Ninja, Node 22, googletest 1.15.2, pixelmatch (new dev-only npm dep under tests/, same precedent as Playwright 1.64), native build with system clang/gcc for goldens.

## Grounding facts (verified against the real trees on 2026-10-13 — do not re-derive)

- Inkscape source: `git clone --depth 1 --branch INKSCAPE_1_4_4
  https://gitlab.com/inkscape/inkscape.git build/src/inkscape-1.4.4` (gitlab
  tarball downloads are Cloudflare-blocked; git clone is not). Submodules are
  NOT fetched — not needed because we use the sysroot lib2geom.
- Hard-REQUIRED deps (no CMake option disables them; verified in
  `CMakeScripts/DefineDependsandFlags.cmake`): harfbuzz ✓, pangocairo ✓,
  pangoft2 ✓, fontconfig ✓, gsl ✓, gmodule-2.0 ✓, **bdw-gc ✓** (libgc 8.2.8,
  `bdw-gc.pc`), lcms2 ✗ **missing**, DoubleConversion ✓ (their
  `FindDoubleConversion.cmake`), PNG ✓, **Potrace ✗ missing**
  (`find_package(Potrace REQUIRED)` + `CMakeScripts/Modules/FindPotrace.cmake`
  → looks for `potracelib.h` + libpotrace), Iconv/Intl (emsdk musl ships both
  `iconv.h` and `libintl.h`), LibXml2/LibXslt ✓, ZLIB ✓, SIGC++ ✓,
  **epoxy ✓** (1.5.11 already in sysroot — a GTK3 dep; the GL-canvas files
  `src/ui/widget/canvas/{glgraphics,pixelstreamer,texture}.*` link against it
  and are runtime-inert), GTK3/gtkmm stack ✓, 2geom ✓ (`2geom.pc` v1.4 found
  via `pkg_check_modules(2Geom QUIET ... 2geom>=1.4)` → `WITH_INTERNAL_2GEOM`
  stays OFF).
- Boost: headers-only today; Inkscape needs
  `find_package(Boost REQUIRED COMPONENTS filesystem)` (plus the optional
  `stacktrace_backtrace`, non-required) → **libboost_filesystem(+stacktrace)
  must be built** (`b2 toolset=emscripten` supports it).
- Real CMake options in 1.4.4 (spec 03's `WITH_DBUS`/`WITH_LIBSOUP`/
  `WITH_ASPELL`/`WITH_GTK_SOURCE_VIEW` don't exist under those names — the
  actual set): `ENABLE_POPPLER`, `ENABLE_POPPLER_CAIRO`, `WITH_IMAGE_MAGICK`,
  `WITH_GRAPHICS_MAGICK`, `WITH_LIBCDR`, `WITH_LIBVISIO`, `WITH_LIBWPG`,
  `WITH_GSPELL`, `WITH_GSOURCEVIEW`, `WITH_NLS`, `WITH_X11`, `WITH_OPENMP`,
  `WITH_GNU_READLINE`, `WITH_JEMALLOC` (default OFF), `WITH_INTERNAL_2GEOM`,
  `WITH_SVG2` (keep ON — feature defines, no new deps), `BUILD_SHARED_LIBS`.
- Process-spawn surface (all runtime-only, none hit by the export pipeline):
  `g_spawn_command_line_async` in `src/actions/actions-element-image.cpp` (open
  containing folder), `popen` in
  `src/extension/internal/cairo-render-context.cpp` (PS-pipe export paths),
  `g_spawn_sync` wrapper in `src/inkscape-version-info.cpp` (lazy debug info).
  glib links fine; stub only if a symbol is actually missing at link time.
- Paths: `src/io/resource.cpp` resolves the share tree via
  `get_inkscape_datadir()` (CMake install-prefix derived) and honors
  `INKSCAPE_EXTENSIONS_DIR`; profile dir honors `INKSCAPE_PROFILE_DIR` env
  (line ~417) → set it to a mounted writable dir. `share/` is 120 MB total;
  needed subsets: `icons` 20M, `ui` 1.6M, `paint` 2.6M, `filters` 228K,
  `keys` 128K (+ `palettes`, `markers`, `templates`, `symbols`, `attributes`,
  `themes`, `fontcollections` — copy everything except `doc/`, `examples/`,
  `tutorials/`, `branding/`, `extensions/`).
- Export actions exist in 1.4.4 (`src/actions/actions-file.cpp`,
  `actions-output.cpp`): `file-open:<path>`, `export-filename:<path>`,
  `export-do`, `file-close`. Batch mode: `--batch-process` runs actions then
  exits without the interactive loop.
- lib2geom tests: `build/src/lib2geom/tests/CMakeLists.txt` —
  `find_package(GTest REQUIRED MODULE)`, 24 gtest binaries
  (`GTest::Main`) + 3 with their own mains (`sbasis-text`, `root-find`,
  `implicitization`). Leg A built with `-D2GEOM_TESTING=OFF`; the flag exists
  (`option(2GEOM_TESTING ...)`, gtest does NOT ship with emsdk → build
  googletest ourselves. ctest can run wasm tests by passing
  `-DCMAKE_CROSSCOMPILING_EMULATOR=node` (cmake prefixes the command).
- Node-side GDK: the gtk3 node smoke test (Leg B) already runs GDK-broadway
  against the real in-module daemon with no browser client — pipe B just
  accumulates unpumped bytes. Headless export creates no toplevel window →
  negligible traffic. T5's driver may optionally call `_bridge_js_poll` to
  drain; not required.
- Goldens: no system inkscape (Ubuntu 26.04 candidate is 1.4.3 — version
  mismatch); inkscape.org AppImage endpoint returns HTML/502 to curl (CDN).
  → Build native 1.4.4 from the same clone with system deps +
  `git submodule update --init src/3rdparty/2geom` + `WITH_INTERNAL_2GEOM=ON`
  (identical 2geom code to the sysroot's). Native build ≠ golden rasterizer
  parity (system cairo/pango differ from ours) — that's what pixelmatch
  tolerances are for (spec 04: 0.1% shape-only, 2% text-heavy).
- Build cost: inkscape wasm build ~30-60 min on 64 cores, native build
  similar — both under `oc-bg`, per session rules.
- Session rules that apply: never `read` PNG/image files (text-only model —
  pixelmatch results are read from its JSON/text output, never eyeballed via
  `read`); package scripts run under bash; long builds via
  `~/.config/opencode/bin/oc-bg <log> -- <cmd>`.

---

### Task 1: Sysroot gaps — lcms2, potrace, boost libs

**Files:**
- Create: `packages/lcms2.sh`, `packages/potrace.sh`, `tests/lib/lcms2_test.c`, `tests/lib/potrace_test.c`
- Modify: `packages/boost.sh`, `tests/check-1.sh`, `Makefile` (PKGS list)

**Interfaces:**
- Consumes: existing `fetch`/`extract_auto`/`ac`/`wasmtest` helpers.
- Produces: `pkg-config: lcms2`, `find_package(Potrace)`-satisfying potrace
  (headers + `libpotrace.a`), `libboost_filesystem.a` (+`libboost_stacktrace*.a`)
  in `$SYSROOT/lib`.

- [ ] **Step 1: `packages/lcms2.sh`** — lcms2 2.16 (github lcms/lcms2 tarball;
  autotools build via `ac lcms2` — it has no wasm-hostile deps). Smoke test:
  create sRGB profile, cmsGetProfileInfoUTF8 non-empty. `manifest lcms2 2.16`,
  stamp.
- [ ] **Step 2: `packages/potrace.sh`** — potrace 1.16 from
  `https://potrace.sourceforge.net/download/potrace-1.16.tar.gz`;
  `ac potrace --with-libpotrace` (builds `libpotrace.a` + `potracelib.h`;
  the CLI binary will fail to link on emscripten — tolerate: install lib+hdr
  only, or `emmake make install` partial). NOTE from Leg A findings: potrace
  *links* cleanly; the trace smoke test returned NULL path lists — do NOT gate
  on tracing behavior, only on library presence (`potrace_version()` string
  non-null). Inkscape only needs configure-time satisfaction + link.
  `manifest potrace 1.16`, stamp.
- [ ] **Step 3: boost libs** — extend `packages/boost.sh` after the header
  copy: `bootstrap.sh`, write `user-config.jam` with
  `using emscripten : : em++ ;`, then
  `./b2 toolset=emscripten link=static threading=multi --with-filesystem
  --with-stacktrace install --prefix=$SYSROOT -j64`. Delete the stamp first
  (`rm build/stamps/boost.ok`). Smoke: wasmtest links a tiny
  `boost::filesystem::path` copy_file program (add `tests/lib/boost_fs_test.cpp`).
- [ ] **Step 4: check-1 extension** — add `lcms2 potrace` to the PKGS and
  pkg-config lists in `tests/check-1.sh` (`lcms2` module only; potrace ships
  no .pc — check `-l` file + header instead). Add both to the Makefile PKGS.
  Re-run `make check-1` (delete `build/stamps/check-1.ok` first — it caches).
- [ ] **Step 5: Run + commit** — `bash packages/lcms2.sh && bash
  packages/potrace.sh && bash packages/boost.sh && make check-1`.
  Commit: `leg C: sysroot gaps — lcms2, potrace, boost filesystem/stacktrace libs`.

---

### Task 2: T4 gate — lib2geom test suite in Node (make check-4)

**Files:**
- Create: `tests/t4/run.sh`, `tests/t4/xfail.txt` (initially empty)
- Modify: `Makefile` (check-4)

**Interfaces:**
- Consumes: `build/src/lib2geom` (Leg A clone), googletest v1.15.2 tarball.
- Produces: `make check-4` → stamp `build/stamps/check-4.ok`; gtest installed
  under `build/test/gtest-root` (test-only, NOT in the sysroot).

- [ ] **Step 1: googletest build** — in `tests/t4/run.sh` (or a small
  `tests/t4/gtest.sh` if it grows): fetch
  `https://github.com/google/googletest/archive/refs/tags/v1.15.2.tar.gz`,
  extract to `build/src/googletest`, build with the existing `cm` helper
  semantics but a private prefix:
  `emcmake cmake -S build/src/googletest -B build/test/gtest -G Ninja
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$BUILD/test/gtest-root
  -Dgtest_build_tests=OFF -Dgmock_build_tests=OFF -DBUILD_GMOCK=OFF` +
  `ninja -j64 && ninja install`.
- [ ] **Step 2: lib2geom test build** — separate build dir (do not touch the
  Leg-A `build/lib2geom`):
  `emcmake cmake -S build/src/lib2geom -B build/test/2geom-tests -G Ninja
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
  -D2GEOM_TESTING=ON -D2GEOM_TOYS=OFF -D2GEOM_PROFILING=OFF
  -DCMAKE_PREFIX_PATH=$SYSROOT
  -DCMAKE_FIND_ROOT_PATH=$SYSROOT
  -DCMAKE_CROSSCOMPILING_EMULATOR=node
  -DGTest_ROOT=$BUILD/test/gtest-root` — if FindGTest (MODULE) ignores
  `GTest_ROOT`, pass `-DGTest_INCLUDE_DIR=... -DGTest_LIBRARY=...
  -DGTest_MAIN_LIBRARY=...` explicitly. Build only the tests dir:
  `ninja -C build/test/2geom-tests -j64` (2geom lib rebuilds with identical
  flags — fine).
- [ ] **Step 3: run** — `ctest --test-dir build/test/2geom-tests
  --output-on-failure --timeout 60` (emulator runs `node <t>.js`). If ctest
  hangs on the wrapper, fall back to a bash loop:
  `for t in build/test/2geom-tests/tests/*-test.js; do timeout 60 node $t ||
  echo FAIL $t; done`. Compare failures against `tests/t4/xfail.txt`
  (format: one binary name per line, comment = reason). Gate: zero failures
  outside the allowlist. Expect: most/all green; allowlist only genuine
  platform bits (e.g. long-double precision, timing tests).
- [ ] **Step 4: `make check-4`** — `tests/t4/run.sh` wraps steps 1-3 with the
  stamp-cache pattern; Makefile `check-4: ; bash tests/t4/run.sh` (+.PHONY).
- [ ] **Step 5: Run + commit** — `make check-4` → PASS. Commit:
  `leg C: T4 gate — lib2geom test suite green in node (make check-4)`.

---

### Task 3: Inkscape wasm build (packages/inkscape.sh + patches)

**Files:**
- Create: `packages/inkscape.sh`, `patches/inkscape/*.patch`, `tests/lib/inkscape_smoke.cpp` (optional)
- Modify: `Makefile` (PKGS + `inkscape` target)

**Interfaces:**
- Consumes: the full sysroot + `bridge/` sources + `daemon_objs()`.
- Produces: `build/inkscape/inkscape.js` + `.wasm` (+ `.data` in Task 4),
  stamp `build/stamps/inkscape.ok`.

- [ ] **Step 1: configure** — `packages/inkscape.sh` with the verified
  option set (all browser-hostile features OFF):

```bash
INKFLAGS="-DENABLE_POPPLER=OFF -DENABLE_POPPLER_CAIRO=OFF
  -DWITH_IMAGE_MAGICK=OFF -DWITH_GRAPHICS_MAGICK=OFF
  -DWITH_LIBCDR=OFF -DWITH_LIBVISIO=OFF -DWITH_LIBWPG=OFF
  -DWITH_GSPELL=OFF -DWITH_GSOURCEVIEW=OFF -DWITH_NLS=OFF
  -DWITH_X11=OFF -DWITH_OPENMP=OFF -DWITH_GNU_READLINE=OFF
  -DWITH_INTERNAL_2GEOM=OFF -DWITH_SVG2=ON -DBUILD_TESTING=OFF
  -DBUILD_SHARED_LIBS=OFF -DENABLE_BINRELOC=OFF
  -DCMAKE_INSTALL_PREFIX=/inkscape"
```

  cmake with the emscripten toolchain (mirror `cm()` but keep the build in
  `build/inkscape`; note `cm()` installs to $SYSROOT — inkscape must NOT
  install, so invoke cmake directly with the same toolchain/find-root args).
  `cmake --build build/inkscape -j 64 --target inkscape`.
  Expect iterative configure failures here — fix each by flag or patch:
  Iconv/Intl detection, FindPotrace, Boost version string. Log under
  `build/logs/inkscape-configure.log` via oc-bg.
- [ ] **Step 2: env patch** — `patches/inkscape/broadway-env.patch`: in
  `src/inkscape.cpp` `main()` (first statement, guarded `#ifdef
  __EMSCRIPTEN__`): `setenv("GDK_BACKEND", "broadway", 1);
  setenv("FONTCONFIG_FILE", "/fixtures/fonts.conf", 1);
  setenv("INKSCAPE_PROFILE_DIR", "/home/web_user", 1);` — same pattern as
  t2/t3. Generate the patch from a pristine copy under /tmp/opencode
  (never edit build/src in place — repo rule).
- [ ] **Step 3: link** — the inkscape target needs the leg-B link flags;
  pass them via cmake:
  `-DCMAKE_EXE_LINKER_FLAGS="-sSTACK_SIZE=8388608 -sALLOW_MEMORY_GROWTH=1
  -sALLOW_TABLE_GROWTH=1 -sEMULATE_FUNCTION_POINTER_CASTS=1
  -sEXIT_RUNTIME=1 -sMODULARIZE=1 -sEXPORT_NAME=Module
  -sEXPORTED_RUNTIME_METHODS=HEAPU8,callMain,FS
  -sINITIAL_MEMORY=1073741824
  -sEXPORTED_FUNCTIONS=_main,_malloc,_free,_bridge_frame,_bridge_js_connect,_bridge_js_write,_bridge_js_poll,_bridge_js_poll_ptr"`
  plus `bridge/bytepipe.c bridge/bridge.c $TEST/daemon/*.o` into the link
  (the broadway GDK backend needs them; link via
  `-DCMAKE_CXX_STANDARD_LIBRARIES` or an object-library CMake patch —
  whichever is least invasive; the daemon objs are prebuilt by `daemon_objs`
  and passed as extra inputs). Iteratively stub missing process symbols
  (`popen`/`fork` if emscripten lacks them) via
  `patches/inkscape/*.patch` — each stub logs one line.
- [ ] **Step 4: boot smoke (node, no data yet)** — run
  `node build/inkscape/inkscape.js --version` (with `Module` shim if
  MODULARIZE) — expect the version banner; this proves gtk init + display
  open + GC init survive. Fix iteratively (this is where GC/locale/FS
  blockers surface — findings.md gets an entry per fight).
- [ ] **Step 5: Run + commit** — stamp `inkscape.ok`. Commit:
  `leg C: inkscape 1.4.4 builds + boots headless in node (--version)`.

---

### Task 4: Fixtures, share/ packaging, native build, goldens

**Files:**
- Create: `tests/fixtures/{basic,text,gradients,transforms,clip-mask}.svg`,
  `tests/golden/gen.sh`, `packages/native-inkscape.sh`, `tests/manifest.json`
- Modify: `Makefile` (`native-inkscape`, `goldens-regen`)

**Interfaces:**
- Produces: `build/inkscape/inkscape.data` (share/ + fonts preload at
  `/inkscape` and `/fixtures`), `tests/golden/*.png` (committed).

- [ ] **Step 1: fixtures** — five small hand-written SVGs per spec 04
  (one feature each; viewBox 300x200; text.svg uses font-family DejaVu Sans;
  no external refs). Commit-worthy: they are the T5 corpus.
- [ ] **Step 2: FS staging + data** — `tools/package-fs.sh` (or inline in
  inkscape.sh): stage `build/inkscape-fs/inkscape/share/...` (share/ minus
  doc/, examples/, tutorials/, branding/, extensions/) +
  `build/inkscape-fs/fixtures/fonts.conf` + DejaVu/Liberation TTFs, then
  `python3 $EMSDK/upstream/emscripten/tools/filepackager.py
  build/inkscape/inkscape.data --preload build/inkscape-fs@/` and link
  `--preload-file build/inkscape-fs@/` into inkscape.js (relink once).
  Expect 30-80 MB data — accepted (spec risk #4).
- [ ] **Step 3: native build** — `packages/native-inkscape.sh`:
  `git -C build/src/inkscape-1.4.4 submodule update --init src/3rdparty/2geom`;
  apt build deps (gtkmm-3.0-dev libgsl-dev libboost-filesystem-dev
  libpotrace-dev liblcms2-dev libdouble-conversion-dev libxml2-dev
  libxslt1-dev libharfbuzz-dev libpango1.0-dev libgc-dev libepoxy-dev
  libgtest-dev cmake ninja-build — verify list at run); configure with the
  SAME OFF flags + `WITH_INTERNAL_2GEOM=ON`, build `build/native/inkscape`,
  target `inkscape`. This is the golden generator — `make native-inkscape`.
- [ ] **Step 4: goldens** — `tests/golden/gen.sh`: for each fixture run
  `build/native/inkscape/bin/inkscape --batch-process --actions
  "file-open:$f; export-filename:tests/golden/$(basename $f .svg).png;
  export-do; file-close"`. Commit goldens (small PNGs). `make
  goldens-regen` wraps it (spec rule: regen needs a stated reason in the
  commit message).
- [ ] **Step 5: Run + commit** — goldens generated for all 5 fixtures.
  Commit: `leg C: T5 corpus — fixtures, share/fonts packaging, native 1.4.4
  goldens`.

---

### Task 5: T5 gate — headless export + pixelmatch (make check-5)

**Files:**
- Create: `tests/t5/run.sh`, `tests/t5/driver.mjs`, `tests/t5/compare.mjs`
- Modify: `tests/package.json` (+pixelmatch +pngjs dev deps), `Makefile` (check-5)

**Interfaces:**
- Consumes: `build/inkscape/inkscape.{js,wasm,data}`, `tests/golden/*.png`,
  `tests/manifest.json` (per-fixture pixelmatch thresholds).
- Produces: `make check-5` → stamp `build/stamps/check-5.ok`;
  `build/t5/<fixture>.png` outputs + diff counts in the log.

- [ ] **Step 1: driver** — `tests/t5/driver.mjs`: instantiate Module with
  `arguments: ['--batch-process', '--actions',
  'file-open:/fixtures/basic.svg; export-filename:/out.png; export-do;
  file-close']`, `EXIT_RUNTIME=1` fires process exit; copy `/out.png` out via
  `FS.readFile` before exit (or export into `/tmp` and read with
  `--preload`-free FS). Wait: exit callback → read the PNG buffer → write
  `build/t5/<name>.png`.
- [ ] **Step 2: compare** — `tests/t5/compare.mjs`: pixelmatch (+
  pngjs) actual vs golden, thresholds from `tests/manifest.json`
  (`basic`/`transforms`/`clip-mask`/`gradients`: 0.1%; `text`: 2%).
  Textual output only (diff counts) — never `read` the PNGs.
- [ ] **Step 3: run.sh + Makefile** — loop fixtures, stamp-cache pattern,
  `check-5: ; bash tests/t5/run.sh`.
- [ ] **Step 4: Run + commit** — `make check-5` → PASS for all five
  fixtures (tune thresholds ONCE if a fixture sits just over, record the
  number + reason in the commit message; systematic diffs → investigate,
  don't threshold around real bugs). Commit:
  `leg C: T5 gate green — headless SVG→PNG export golden-matches in node`.

---

### Task 6: Findings + roadmap update

**Files:**
- Modify: `docs/findings.md`, `docs/superpowers/plans/2026-10-12-inkscape-wasm-roadmap.md`

- [ ] **Step 1:** Append a "Leg C / T4-T5" section to `docs/findings.md`:
  gate results (date, PASS, artifacts), the spec-03 option-name corrections,
  every configure/link fight and its fix, potrace revisit note (why the
  Leg-A cut was reversed), pixelmatch threshold table, module/data sizes.
- [ ] **Step 2:** Roadmap table row 3 → done, link this plan.
- [ ] **Step 3:** Commit: `leg C: findings + roadmap — T4/T5 green, leg C complete`.

---

## Risks / fallbacks (decision points during execution)

- **Boost.Stacktrace on emscripten**: if `--with-stacktrace` fights, check
  whether the optional `stacktrace_backtrace` find can be made to fail
  cleanly (it must NOT fall into the REQUIRED `stacktrace_basic` branch
  without the lib) — worst case patch DefineDependsandFlags to skip
  stacktrace entirely on `__EMSCRIPTEN__` (crash traces are meaningless in
  wasm anyway).
- **GC at inkscape scale**: libgc passed the Leg-A rung; if T5 hits GC
  crashes, the stub-GC fallback (risk #1 mitigation) is a libgc rebuild,
  not an inkscape change.
- **`--batch-process` main-loop block**: if the actions pipeline ends up
  waiting on a glib poll that never wakes in node, call `bridge_frame()`
  from a `setInterval` inside the driver (the t2 page pattern, minus rAF).
- **Module size at link**: if lld/wasm-opt chokes on the ~400 MB module,
  drop `-g1` (use `-g0`) and/or `--gc-sections`; if wasm-opt OOMs, skip it
  (`-sWASM_BIG` is not needed; closures default off).
- **Native build failures** (apt version skew etc.): fallback = pin the
  Ubuntu 1.4.3 package and document the version gap in findings + widen the
  text threshold; only if even that fails, hand-write goldens from the wasm
  build of a *frozen* fixtures commit (last resort — weakens the gate).
