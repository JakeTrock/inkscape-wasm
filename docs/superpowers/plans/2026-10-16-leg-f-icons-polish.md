# Leg F — Icons, Zero-Error Boot & Harness UX Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the browser-served Inkscape WASM build usable for a human on the tailnet: all toolbar/toolbox/menu/widget icons render, boot produces zero GLib/GTK/Inkscape CRITICAL or WARNING errors, the harness toolbar no longer covers Inkscape's menu bar, and Save works on a fresh canvas without requiring Open first. Validated by a new **T8** Playwright gate (`make check-8`).

## Root-Cause Audit (verified 2026-10-16 against live build)

1. **No icons load anywhere in the UI**
   - All 1,868 symbolic icons (`multicolor`, `hicolor`, `Dash`), 715 `Adwaita` symbolic icons, and 1,750 scalable icons in `build/inkscape-fs` are `.svg`.
   - WASM `gdk-pixbuf` has only `png,jpeg` built in (no `librsvg`), so `GtkIconTheme`'s `priv->pixbuf_supports_svg` is `FALSE`. `best_suffix()` ignores all `.svg` files and falls back to `image-missing.png`, which Leg C seeded with `tests/fixtures/tiny.png` (a 1×1 transparent pixel).
   - Also, when `showwelcome=0` skips `StartScreen`, `ThemeContext::add_gtk_css()` (`src/ui/themes.cpp:286`) overwrites `/theme/defaultIconTheme` with Broadway's default `"Adwaita"` unless `/theme/iconTheme` is explicitly set in `preferences.xml`.
   - **Solution:** GTK3 has native, SVG-free support for symbolic icons via `.symbolic.png` (`gtk_icon_info_load_symbolic_png` in `gtkicontheme.c`, which loads a PNG whose R/G/B/A channels encode base/success/warning/error weights and recolors them in C at runtime to Inkscape's CSS theme colors). The host already has `/usr/bin/gtk-encode-symbolic-svg` (verified: converts `multicolor/symbolic/actions/draw-rectangle-symbolic.svg` into a 163-byte 16×16 `.symbolic.png` with both outline and `.warning` fill channels intact). Non-symbolic `scalable/` SVGs can be batch-rasterized to `.png` during `inkscape-fs` staging using host `libgdk_pixbuf-2.0.so` (which has the host SVG loader). Original `.svg` files in `cursors/` are kept intact because `load_svg_cursor()` (`src/ui/cursor-utils.cpp`) parses cursor SVGs directly via Inkscape's own `SPDocument`.

2. **Console errors and warnings on every boot**
   - `pthread_create suppressed; JS trace follows` + two 10-line stack traces: leftover debug `emscripten_run_script("console.warn(...)"); emscripten_run_script("console.trace()");` in `packages/pthread_supp.c:20-21`.
   - `GLib-CRITICAL **: g_path_get_dirname: assertion 'file_name != NULL' failed`: `src/path-prefix.cpp:256` calls `g_path_get_dirname(get_program_name())`; on Emscripten there is no `/proc/self/exe`, so `get_program_name()` returns `nullptr`.
   - `GModule-CRITICAL **: g_module_symbol: assertion 'module != NULL' failed` and `g_module_close: assertion 'module != NULL' failed`: `gtk/gtkmodules.c:585` (`_gtk_module_has_mixed_deps`) calls `g_module_open(NULL, 0)` which returns `NULL` on static WASM, then calls `g_module_symbol(module, ...)` and `g_module_close(module)` without a null check.
   - `Gtk-WARNING **: Could not load a pixbuf from /org/gtk/libgtk/theme/Adwaita/assets/bullet-symbolic.svg`: `gtk/theme/Adwaita/gtk-contained{,-dark}.css` lists `-gtk-recolor(url("assets/bullet-symbolic.svg"))` before `bullet-symbolic.symbolic.png`, logging a warning before falling back to the `.symbolic.png` resource that is already compiled into `libgtk-3.a`.
   - `WARNING **: Can't open file: /home/web_user/cphistory.xml (doesn't exist)`: `src/ui/dialog/command-palette.cpp:1377` logs a warning if `cphistory.xml` is absent from the profile dir.
   - `Shortcut::read: file does not exist: /inkscape/share/inkscape/keys/default.xml`: CMake's install rule copies `share/keys/inkscape.xml` to `default.xml`, which our manual `cp -r` staging skipped.
   - `Gtk-CRITICAL **: invalid accelerator string ''` / `gtk_application_accels_get_actions_for_accel: assertion 'accel_key.key != 0' failed` / `Gtk-WARNING **: Unable to parse accelerator ''`: `share/keys/inkscape.xml` has two `<bind ... keys=""/>` entries (lines 112, 120); `Shortcuts::add_shortcut()` (`src/ui/shortcuts.cpp:523`) passes empty `Gtk::AccelKey` objects into `remove_shortcut()` and `set_accels_for_action()`.
   - Raw ANSI escape sequences (`\x1b[1;35mCRITICAL\x1b[0m`) appear in `#console` because GLib formats log output with ANSI escapes and `loader.js` writes `textContent` verbatim.

3. **Harness layout & Save UX**
   - `broadway.js` appends `body > canvas` positioned at `(0, 0)` of the viewport, while `#toolbar` + `#stagebar` sit at `y = 0..52` with `z-index: 10`, occluding Inkscape's menu bar (`File Edit View...`) and top toolbar.
   - Clicking `Save` on a newly booted session without clicking `Open SVG` first refuses (`Save: no file opened — open a file first`) because the startup template has no filename.

---

### Task 1: Pre-encode icon themes (`.symbolic.png` + `.png`) and set `multicolor` in prefs

**Files:**
- Create: `packages/encode-icons.py` (host helper using `/usr/bin/gtk-encode-symbolic-svg` + `libgdk_pixbuf-2.0.so` in parallel across CPU cores)
- Modify: `packages/inkscape.sh`, `tests/fixtures/inkscape-prefs.xml`

**Steps:**
- [x] **Step 1:** Write `packages/encode-icons.py`:
  - Walk `$FS/inkscape/share/inkscape/icons` and `$FS/inkscape/share/icons`.
  - For every `*-symbolic.svg` (and `*-symbolic-ltr.svg`, `*-symbolic-rtl.svg`), run `/usr/bin/gtk-encode-symbolic-svg <svg> 16x16 -o <dir>` across a process pool so `foo-symbolic.symbolic.png` sits next to `foo-symbolic.svg`.
  - For non-symbolic `.svg` files outside `cursors/` (e.g. `scalable/**/*.svg`), rasterize via host `libgdk_pixbuf-2.0.so` (`gdk_pixbuf_new_from_file_at_scale` → `gdk_pixbuf_save(..., "png")`) to `<stem>.png` in the same directory so `best_suffix()` picks `ICON_SUFFIX_PNG`.
  - Delete any `icon-theme.cache` files afterward so `GtkIconTheme` rescans directory entries.
- [x] **Step 2:** Update `tests/fixtures/inkscape-prefs.xml` to include:
  ```xml
  <group id="theme" iconTheme="multicolor" defaultIconTheme="multicolor" symbolicIcons="1"
         preferDarkTheme="1" darkTheme="1" symbolicDefaultBaseColors="1" symbolicDefaultHighColors="0"/>
  ```
- [x] **Step 3:** Wire `python3 packages/encode-icons.py "$FS"` into `packages/inkscape.sh` (guarded by a stamp file inside `$FS` so it runs once per FS stage).

---

### Task 2: Silence all boot CRITICALs and WARNINGs in `pthread_supp`, `gtk3`, and `inkscape`

**Files:**
- Modify: `packages/pthread_supp.c`
- Create: `patches/gtk3/clean-boot-emscripten.patch`, `patches/inkscape/clean-boot-emscripten.patch`
- Modify: `packages/gtk3.sh`, `packages/inkscape.sh`

**Steps:**
- [x] **Step 1 (`packages/pthread_supp.c`):** Remove the debug `emscripten_run_script("console.warn(...)"); emscripten_run_script("console.trace()");` calls from `pthread_create`; rebuild `pthread_supp.ok`.
- [x] **Step 2 (`patches/gtk3/clean-boot-emscripten.patch`):**
  - In `gtk/gtkmodules.c` (`_gtk_module_has_mixed_deps`), add `if (!module) return FALSE;` after `module = g_module_open (NULL, 0);`.
  - In `gtk/theme/Adwaita/gtk-contained.css` and `gtk-contained-dark.css`, replace `-gtk-recolor(url("assets/check-symbolic.svg")), ` / `bullet-symbolic.svg` / `dash-symbolic.svg` with the `.symbolic.png` URLs so GTK never attempts to SVG-decode the GResource assets before using the `.symbolic.png` assets.
  - Rebuild `pkg-gtk3` (updates `libgtk-3.a` and its compiled GResources).
- [x] **Step 3 (`patches/inkscape/clean-boot-emscripten.patch`):**
  - In `src/path-prefix.cpp` (`get_program_name`), under `#ifdef __EMSCRIPTEN__`, return `"/inkscape/bin/inkscape"` instead of `nullptr`.
  - In `src/ui/shortcuts.cpp` (`Shortcuts::add_shortcut`), guard `if (shortcut.is_null() || shortcut.get_abbrev().empty()) return false;` at entry.
- [x] **Step 4 (`packages/inkscape.sh` FS staging):**
  - Copy `$SRC/inkscape-1.4.4/share/keys/inkscape.xml` to `$FS/inkscape/share/inkscape/keys/default.xml`.
  - Seed `$FS/home/web_user/cphistory.xml` with `<?xml version="1.0" encoding="UTF-8"?><cphistory/>`.
  - Rebuild `pkg-inkscape`.
- [x] **Step 5:** Run `node tests/t6/boot-smoke.mjs` and verify zero `CRITICAL`, `WARNING`, or `pthread_create` lines appear on stdout/stderr.

---

### Task 3: Fix harness layout, console ANSI formatting, and Save on fresh canvas

**Files:**
- Modify: `harness/index.html`, `harness/loader.js`

**Steps:**
- [x] **Step 1 (Canvas occlusion fix):**
  - Check how `broadway.js` places top-level surfaces (`body > canvas`) and how `broadway-server.c` sets the initial screen/window size (`1024×768`).
  - Offset `body > canvas` below `#toolbar` + `#stagebar` (or dock `#console` as a collapsible bottom drawer) and translate mouse event coordinates if needed — wait: `broadway.js` uses `getSurfaceId(ev)` / `ev.pageX - canvas.offsetLeft` (or `getBoundingClientRect()`). Verify how `broadway.js` computes mouse coordinates before applying CSS `top` / `margin-top` so canvas click/drag coordinates remain exact!
- [x] **Step 2 (Save without prior Open):**
  - In `harness/loader.js`, if `docPath` is `null` when clicking `Save`, save to `DOCS + '/drawing.svg'` via `export-filename:/home/web_user/documents/drawing.svg;export-do`, set `docPath = DOCS + '/drawing.svg'`, download the SVG, and flush IDBFS.
- [x] **Step 3 (Console log hygiene):**
  - Strip ANSI escape codes (`/\x1b\[[0-9;]*m/g`) in `conlog()`.
  - Only apply `.err` styling when a stderr line matches `/CRITICAL|ERROR|Uncaught|RuntimeError/i` (or `err === 'fatal'`), keeping normal info lines neutral.

---

### Task 4: T8 gate — icons rendered, zero console errors, fresh-Save (`make check-8`)

**Files:**
- Create: `tests/t8/run.sh`, `tests/t8/t8.spec.ts`
- Modify: `Makefile`, `docs/findings.md`, `docs/superpowers/plans/2026-10-12-inkscape-wasm-roadmap.md`

**Steps:**
- [x] **Step 1:** Write `tests/t8/t8.spec.ts`:
  - Boot `/harness/index.html` and collect all console/pageerror lines.
  - Assert zero `CRITICAL`, `WARNING`, `pthread_create`, or `pageerror` messages.
  - Inspect the left toolbox column (`x ∈ [4, 34]`) across multiple vertical icon slots (`y = 100..500`) and the top toolbar (`y ∈ [30, 95]`): assert multiple distinct icon bounding boxes contain non-background foreground/highlight pixels (proving icons actually rendered).
  - Assert the top of the Inkscape canvas (`canvas.getBoundingClientRect().top`) is not hidden behind `#toolbar` / `#stagebar`.
  - Draw a rectangle on the fresh default canvas (without opening a fixture) and click `#btn-save`; assert `/home/web_user/documents/drawing.svg` exists and contains the drawn `<rect>`.
- [x] **Step 2:** Re-verify `make check-6 check-7 check-8` all PASS and re-stage `build/harness/` for the running tailnet server.
- [x] **Step 3:** Commit and update `docs/findings.md` + `docs/superpowers/plans/2026-10-12-inkscape-wasm-roadmap.md`.
