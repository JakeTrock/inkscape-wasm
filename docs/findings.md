# Findings — Inkscape WASM port (Leg A)

Running log of deviations from plan, toolchain quirks, and hard-won facts.

## Toolchain (emcc 6.0.6, shared emsdk at /data/jake/reversing/toki/emsdk)

- **`-sEXPORTED_FUNCTIONS` REPLACES the default export list** — `_main` must be
  listed explicitly or main silently never runs (tests pass vacuously with
  exit 0 and no output). wasmtest now exports `_malloc,_free,_main`.
- **emcc drops `-lpthread` from link lines** — pass
  `$SYSROOT/lib/libpthread.a` by absolute path instead (wasmtest appends it
  to every link; the generated cross file uses the same trick).
- **Wasm strict function types**: function-pointer casts that native ABIs
  tolerate (1-arg function called through a 2-arg typedef) crash at runtime
  with `null function or function signature mismatch`. This hit glib in
  THREE places, each fixed once in shared code:
  1. `G_DEFINE_TYPE`/`G_DEFINE_INTERFACE` macros generate 1-arg
     `class_intern_init`/`_init`/`_default_init` registered as 2-arg
     callbacks — `patches/glib/gtype-h-wasm-signatures.patch` adds 2-arg
     wrappers in gtype.h (every GObject consumer compiles against it).
  2. `GParamSpecTypeInfo.instance_init` is declared 1-arg but invoked 2-arg
     by gtype.c — `gparam-h-instance-init-type.patch` (field →
     GInstanceInitFunc) + `gparamspecs-instance-init-signatures.patch`
     (22 param_*_init fns made 2-arg, initializer sites cast).
  3. `G_IMPLEMENT_INTERFACE(X, f)` registers 1-arg `f` as 2-arg
     GInterfaceInitFunc; the macro can't wrap (no type name in scope), so
     `iface-init-signatures.patch` per package mechanically adds the 2nd
     param: glib (125 fns), gtk3 (162), pango (7), gdk-pixbuf (2),
     atk (3). Generator: /tmp/opencode/fix_iface_init.py (regenerate if a
     package update changes the set).
  Also `g_object_do_class_init` lost its unused 2nd param upstream —
  `class-init-signature.patch`.
  The *mm bindings' generated `iface_init_function(void*, void*)` glue is
  already 2-arg — no changes needed there.
  Expect more strict-signature bugs in hand-written casts — fix at the call
  site when they surface.
- **`-sALLOW_TABLE_GROWTH=1` is required for libffi closures** (GObject
  signal marshalling grows the wasm table at runtime). wasmtest adds it
  globally; the final Inkscape link will need it too.
- libc's non-mt pthread stubs (library_pthread_stub.c) now cover mutexes,
  cond (incl. timedwait), once, **a complete TLS set with destructors**
  (key_create/key_delete/getspecific/setspecific), rwlocks, barriers.
  `packages/pthread_supp.c` is slimmed to only: pthread_getname_np,
  pthread_getaffinity_np, __sched_cpucount, res_query (HOST_NOT_FOUND),
  ftw (returns -1). Do NOT define pthread_setspecific/getspecific
  yourself — duplicate-symbol errors against libc's strong definitions,
  and mixing your key table with libc's returns EINVAL.
- meson injects `-pthread` + PTHREAD_POOL_SIZE into *executables* only —
  hence the "libraries only + `meson install --no-rebuild`" pattern for
  packages whose test tools can't link (glib, glibmm, cairomm, pangomm,
  atkmm, gtkmm).
- meson `cc.links`/`has_function` probes pass for functions emscripten
  headers declare but non-mt libc lacks (posix_spawnp, pthread_getname_np,
  pthread_getaffinity_np, ftw) — undefined symbols only appear at real
  links. Stubs live in pthread_supp.c.
- cmake ≥4 dropped compatibility with `cmake_minimum_required < 3.5` —
  pcre2 10.42 and double-conversion 3.3.0 need
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.
- GNU tarballs with old `config.sub` (gsl 2.8) don't know emscripten —
  copy /usr/share/misc/config.{sub,guess} over them.
- ccache sits in front of emcc/em++ via common.sh (CC="ccache emcc").

## Package notes

- **glib 2.88.0** (bumped from 2.82 to match the host's glib dev tools
  exactly — host gdbus-codegen 2.88 emits symbols older target glib lacks;
  host tools via `libglib2.0-dev-bin` apt package). Six patches in
  patches/glib/ plus the two signature patches above. Post-install:
  gio-2.0.pc tool variables rewritten to /usr/bin. thread_dep patched to
  `[]` on emscripten — without -pthread, clang lowers __atomic/__sync
  builtins to plain wasm ops (verified empirically).
- **pango 1.56.4** — 1.58 rejected (needs glib ≥2.84 subproject);
  2-arg pango_layout_new is gone, use pango_layout_set_font_description.
- **gdk-pixbuf 2.44.4** — jpeg via its libjpeg-turbo subproject;
  `-Dthumbnailer=disabled` (feature option, not boolean).
- **gtk3 3.24.43** — broadway only; `-Dbuiltin_immodules=all` (NOT "none" —
  that builds everything as shared modules, which need -fPIC and fail);
  print backends patched out on emscripten (they're hardwired
  shared_module; printing cut for v1). broadwayd.js links on wasm — the
  Leg-B donor artifact. `gdkbroadway.h` must be included explicitly for
  GDK_IS_BROADWAY_DISPLAY.
- **sigc++ 2.12.1** — GNOME URL-encodes `libsigc%2B%2B`; tarballs ship
  meson (no generated configure). Pass pkg-config output UNQUOTED to
  wasmtest (quoted becomes one arg).
- **glibmm 2.66.7** — installs libglibmm_generate_extra_defs-2.4.a with no
  .pc; we write one (meson's find_library can't see our sysroot). Other
  *mm packages' extra-defs generator tools are maintainer-only — patched
  out on emscripten (pangomm/atkmm/gtkmm).
- **cairomm 1.14.4** — GNOME pruned the 1.14 dir; canonical tarball is on
  cairographics.org.
- **pangomm 2.46.3 provides the pangomm-1.4 ABI** (not pangomm-2.48);
  gtkmm 3.24.9 requires pangomm-1.4 — consistent.
- **atkmm 2.28.4** required by gtkmm (the plan missed it).
- **libxml2 2.13.6** — `-Dlegacy=true` (libxslt 1.1.42 uses the
  __xml*-prefixed globals); threads stay enabled (same reason); post-fix
  the .pc Cflags (`-I${includedir}/libxml2`, strip meson's injected
  -pthread); meson installs no xml2-config so we generate a sysroot one
  and PATH-prepend it — libxslt's configure otherwise picks the host's
  (2.15.2) and version-skews.
- **libxml2 .pc option types are booleans** (history/http/ftp/readline),
  not feature strings.
- **libgc 8.2.8** — real collector passed rung 1 (finalizer ran, cyclic
  garbage bounded). `GC_INIT;` is wrong — GC_INIT is a function-like
  macro; call `GC_init()`. bdw-gc installs bdw-gc.pc; aliased to gc.pc
  (Inkscape looks up module 'gc').
- **double-conversion** (cmake) installs no .pc — we hand-write
  double-conversion.pc.
- **harfbuzz 14.6.0** rebuilt with `-DHB_NO_MT` (via c_args/cpp_args):
  without pthreads it falls back to std::mutex, poisoning every C-link
  that pulls it. Single-threaded no-op mutex is correct for us.
- **gsl 2.8 / boost 1.86 headers / dconv 3.3.0** — uneventful.

## Test infrastructure

- wasmtest: `|| return 1` guards on compile and node run (a set +e context
  previously let failures print PASS); `-sEXPORTED_FUNCTIONS=_malloc,_free,_main`
  (see above); appends `$SYSROOT/lib/libpthread.a`; `-sALLOW_TABLE_GROWTH=1`.
- **Never trust a PASS without the test's own printf output** in the log —
  the main-export bug made months of PASSes vacuous if module output is absent.
- tests run in Node via `cd build/test && node X.js`; fixtures preloaded at
  /fixtures from tests/fixtures.
- retest helper: /tmp/opencode/retest.sh evals every packages/*.sh wasmtest
  line against the installed sysroot (libs already built).

- **potrace CUT** (Task 19 optional rule): 1.16 builds and links cleanly,
  but potrace_trace returns status OK with a NULL path list even for a
  fully-black bitmap (3 iterations — cut per "skip on any friction").
  Inkscape bitmap-tracing degrades; revisit in Leg C+ if needed.

## Deferred / shortcuts

- `res_query` stub: no DNS in wasm — gio resolver fails clean. When to
  upgrade: never, unless we want network in the browser build.
- `ftw` stub: returns -1; only exists so gtk's host-side tools link.
- Leak-by-design: libc's TLS destructors never run at exit (no thread exit
  in non-mt); acceptable for single-document demo sessions.

## The wasm strict-signature endgame (glib stack, 9-package chain)

The systemic class: C code casts function pointers across arities (native
ABI tolerates the mismatch, wasm traps). Four sub-classes fixed, then one
link-time catch-all:

1. **G_DEFINE_* registrations** (gtype.h macro wrappers) — patched in
   glib's header; every consumer compiles against it. Consumers'
   `_class_init`/`_init`/`_default_init` targets invoked 1-arg by the
   macro wrapper must STAY 1-arg.
2. **iface/class/instance init hand-registrations** — generator
   (/tmp/opencode/fix_iface_init.py) patches prototypes+defs to 2-arg.
   Final counts: glib 160/101 files, pango 11/10, gdk-pixbuf 2/1,
   atk 17/16, gtk3 268/167. Generator traps found the hard way:
   - a global `re.sub(count=1)` can match an earlier site with identical
     param text and silently shift every remaining match offset (the
     gdummytlsbackend enum garble) → build replacements positionally from
     `m.start(2)`/`m.end(0)`;
   - typedefs in gmarshal.c are function-local (each marshal fn redefines
     its own) → insert `_CLASS` variants after EVERY occurrence;
   - pointer return types (`gchar*`) break `\w+` typedef regexes;
   - defs in files WITHOUT references (public fns like
     _gtk_file_chooser_delegate_iface_init) need a phase-2 alternation
     sweep over all files — but skip G_DEFINE_*-macro-protected names in
     that file (gtk_clipboard_class_init is registered via a hand-written
     cast in gtkclipboard-quartz.c but called 1-arg by the macro wrapper
     in the built gtkclipboard.c);
   - direct 1-arg callers of newly-2-arg functions: only the two
     filechooser delegate call sites (patches/gtk3/filechooser-delegate-
     calls.patch, based on post-iface state).
3. **gmarshal class-closure callbacks**: signals registered via
   G_STRUCT_OFFSET(Class, member) have members without trailing
   user_data, but g_cclosure_marshal_* called them WITH data2.
   Fixed centrally in gmarshal.c (44 invocations + 44 function-local
   `GMarshalFunc_*_CLASS` typedefs; marshal_data non-NULL ⇒ class member
   ⇒ call sans data2). Fixed the atk notify crash.
4. **pango fontconfig worker thread**: g_system_thread_new → pthread_create
   ENOTSUP. patches/pango/fc-thread-inline.patch runs the 4 worker ops
   inline on emscripten.
5. **glib comparator casts (g_list_insert_sorted & co)**: 2-arg
   GCompareFuncs called through 3-arg GCompareDataFunc types all over
   glist/gslist/garray/gtree — NOT patched. Instead:
6. **`-sEMULATE_FUNCTION_POINTER_CASTS=1`** (LINK-only setting — as a
   compile arg it trips meson's -Werror=unused-command-line-argument;
   link-only application to .o files is sufficient, verified) — binaryen
   wasm-opt --fpcast-emu generates thunks for all table entries. This
   catches the whole tail (list sorts, qsort comparators, ...).
   Constraints found:
   - **fpcast-emu 16-param limit**: table-resident functions with ≥17
     params abort the link ("max-func-params needs to be at least 17").
     Fixed in gdk-pixbuf: check_size/color1/color2 were unused in the
     4 pixops line funcs; bundled into a `PixopsCheck*` pointer
     (patches/gdk-pixbuf/pixops-line-func-params.patch, 17→15 params).
     The 4 g_spawn/fork_exec 17+-param fns are NOT table-resident — no
     fix needed. Expect more of these in the Inkscape link; fix by
     param-bundling or de-tabling.
   - **fpcast breaks libffi's JS ffi_call_js** (it .apply()s table
     entries directly; thunks aren't transparent). libffi's own test
     links without fpcast. Runtime constraint for the final link:
     ffi_call must not execute — gtk/gtkmm signal closures all use
     direct-specific marshals, so the stack is unaffected today.
     Revisit if anything needs g_cclosure_marshal_generic at runtime.
   - gtk's tool executables (gtk-update-icon-cache etc.) exceed the
     fpcast limit → gtk3.sh builds only the libs + broadwayd.js + locale
     gresources + libgail-util (targeted ninja targets), not `ninja all`.

## Broadway without a daemon (T5 gate)

- `Unable to read from broadway server` → exit(1): display_open needs a
  server handshake. patches/gtk3/broadway-fake-server-emscripten.patch
  fakes it under __EMSCRIPTEN__: no connection (messages dropped),
  synthesized replies for the 5 round-trip request types, unique fake
  window ids, synthesized CONFIGURE_NOTIFYs on new_window and
  move_resize (GTK freezes toplevel updates after every resize request
  and only thaws on the configure notify — without it nothing ever
  paints), and map_named_shm → plain g_malloc0 (emscripten mmap returns
  MAP_FAILED; the window surface wrapped address -1).
- **wasm stack**: 64KB default is far too small — GTK's realize path
  overflows into "memory access out of bounds" deep in gettext/strlen.
  -sSTACK_SIZE=8388608 added to wasmtest + cross-file link args.
- Fontconfig with no config file: label heights come out nondeterministic
  garbage (12800px-class) across builds. Harmless for the T5 test; ship a
  minimal fonts.conf in Leg B.
- Result: `gtk-broadway ok (display GdkBroadwayDisplay, drew 1 frames)` —
  window + label realize, map, and one full draw pass in node.

## T1 gate result (2026-10-13)

- 9-package chain green: glib pango gdk-pixbuf atk gtk3 glibmm pangomm
  atkmm gtkmm (chain32). Full retest of all 28 wasmtest lines: PASS
  (libffi re-verified without fpcast; libgc rung 1: finalizer runs, heap
  bounded). check-1 PASS: 65 manifest entries, all stamps + pkg-config
  modules (incl. 2geom, gc) resolve. potrace stays cut.
- Donor artifacts: build/donor/broadwayd.{js,wasm} preserved for Leg B.
- Patch hygiene: overlapping patches (iface-init + calls/fc-thread, both
  based on post-iface state) break each other's reverse-dry-run guards —
  gtk3.sh and pango.sh now wipe their source dir before extract.

## Leg B — broadway bridge (T2/T3 gates, 2026-10-13)

- Gates PASS: `make check-2` (GTK C hello world: label text rasterizes,
  button click → "button clicked" console line) and `make check-3`
  (gtkmm: `signal_clicked` fires + cairo red rectangle). Playwright
  drives a real browser tab; artifacts `build/t2/t2-shot.png`,
  `build/t3/t3-shot.png`, stamps `build/stamps/check-{2,3}.ok`.
  Plan: `docs/superpowers/plans/2026-10-13-leg-b-broadway-bridge.md`
  (executed task-by-task; all tasks done).
- Architecture as built — the four spec deviations, all deliberate:
  1. **Pipe A is self-pumping**: a write hook on the pipe's daemon end
     calls `broadway_client_process_buffered` synchronously, so in the
     single-threaded module every GDK round-trip resolves inside the
     write call that triggered it.
  2. **Main loop = spec's fallback design**: exported `bridge_frame()`
     runs `g_main_context_iteration(NULL, FALSE)` once per rAF tick.
     Asyncify was not needed.
  3. **WebSocket framing kept on the daemon↔JS seam**: `bridge/bridge.js`
     `BridgeSocket` frames/unframes; `parse_input` and `broadway.js`
     work unpatched (one sed swaps `new WebSocket(...)` for
     `new BridgeSocket()` in the shipped broadway.js copy).
  4. **shm = name→pointer registry** in bridge.c: `map_named_shm` hands
     the daemon the app's heap pointer; surfaces are never freed
     (bounded leak per window resize); `shm_data_unmap` no-ops.
- `g_pollable_source_new`-created sources never dispatch on wasm
  (prepare/check are NULL) — bytepipe.c implements its own
  `BridgePollSource` polling `is_readable`; used by both pipe ends and
  the daemon's `BroadwayInput`.
- Stock broadwayd `client_fill_cb` spins forever on a partial trailing
  request; the broadwayd patch adds the missing `else break;`.
- Daemon sources need `-DGDK_COMPILATION`, which must not leak into app
  code → `daemon_objs()` (packages/common.sh) compiles them to .o
  separately. `build_harness` now does the same for the bridge .c files
  whenever the app is C++: em++ compiles them as C++ and rejects the
  implicit `void*` casts GObject C relies on.
- Harness quirks: broadway.js needs `Zlib` from `rawinflate.min.js`
  (copied into every harness dir, loaded before broadway.js) and the
  module must export `HEAPU8` (`pumpDaemon` reads it).
- **CSD click geometry** (cost a debugging session): the toplevel
  surface is 352x289 — 300x200 content plus a (26,60) margin (shadow +
  client-side titlebar) — and the daemon parks it at (-26,-23) so the
  *content* sits at the requested (0,0). GtkButton's input-only event
  window lands at surface (46,180)-(146,220); specs click
  canvas-relative (96,200). GDK-side routing (daemon reports the
  toplevel id, `_gdk_window_find_descendant_at` resolves the
  input-only child) works unpatched — only the test coordinates were
  wrong.
- **glib ctor ordering** (C++ apps): gtkmm static initializers call
  glib before glib's own *unprioritized* `glib_init` constructor runs →
  `quark_ht` stays NULL → CRITICALs → `g_quark_init` assert → abort
  before main. bridge.c installs `constructor(101)` calling
  `glib_init()` (idempotent, so C apps are unaffected); bridge.o also
  precedes the archives in link order, so it wins even if wasm-lld
  ignored priorities.
- gtkmm windows must be heap-allocated and leaked: a stack C++ wrapper
  destructs when main() returns and tears the window down with it.


## Leg C — inkscape headless build (T4/T5 gates, 2026-10-13)

Inkscape 1.4.4 (dcaf3e7) compiles 1019/1019 targets and links; the module
boots in node and batch-exports SVG→PNG pixel-identical to native
(`make check-5`: basic/gradients/transforms/clip-mask 0.000%, text 1.787%).

### Link gotchas

- **Link at `-O1`** (compile stays -O3): emcc runs fpcast-emu at -O1 but
  skips `--post-emscripten`/-O3, dodging a binaryen `mixed_arena.h:188`
  assert. fpcast-emu still needs `--pass-arg=max-func-params@64`
  (KEY@VALUE form; inkscape needs 44 params; 32 re-fatal'd).
- **Bridge/daemon objects belong in a static archive** (`-linkbridge` pulls
  `libinkbridge.a`): loose .o files in global linker flags leak into every
  cmake try_compile and break Iconv/LIBATOMIC checks.
- **ninja cannot see `-l` libraries**: after rebuilding glib, an inkscape
  relink must be forced by deleting `build/inkscape/bin/inkscape.{js,wasm}`;
  a stale `inkscape.ok` stamp once survived a "successful" build this way.
- cmake caches pkg-config results (`LIBXML_LDFLAGS:INTERNAL`): delete
  CMakeCache.txt + CMakeFiles before reconfiguring after .pc edits
  (libxml-2.0.pc must not carry meson's `-pthread -sPTHREAD_POOL_SIZE=4` —
  it silently turns the link into an MT build; 2geom.pc needs
  `-lgsl -lgslcblas -ldouble-conversion` appended).
- Boost must be built `address-model=32` or the generated cmake variant
  files carry the wrong `CMAKE_SIZEOF_VOID_P` polarity for wasm32.

### Boot / single-threading (the hard-won part)

- **gobject ctor race**: app objects' static ctors (GType registrations)
  precede archives in link order, so gobject's own ctor lost the race →
  `static_quark_type_flags` assert. `gobject-ctor-priority.patch` gives it
  `constructor(101)` under `__EMSCRIPTEN__` (mirrors bridge.c's glib trick).
- **`pthread_create` is suppressed, not failed** (pthread_supp.c): glib's
  `g_system_thread_new` g_error's on failure. A fake handle + return 0 lets
  GDBus workers and friends "exist" dead while boot proceeds.
- **`g_thread_pool_push` runs jobs inline** (`gthreadpool-inline-push.patch`):
  GTK loads its IM module through GTask → the global pool waits for a worker
  that can never start → 100% CPU spin in `g_cond_wait`, forever. Inline
  execution makes async GTask users complete synchronously.
- **Headless switch**: `GDK_BACKEND=unsupported` (env respected by the
  broadway-env patch) makes `gtk_init_check` fail → `_with_gui=false` →
  batch actions run windowless. With broadway, `create_window` blocks
  waiting for a client that headless tests never provide.
- **Icon themes**: widget init aborts without `image-missing`. Adwaita ships
  it SVG-only and wasm gdk-pixbuf has no SVG loader — seed 1x1 PNGs into
  Adwaita/hicolor size dirs (they beat scalable/ in lookup order) and delete
  the host `icon-theme.cache` files or GTK trusts the stale cache and never
  rescans. `XDG_DATA_DIRS=/inkscape/share`.
- **share/ layout**: inkscape looks under `<prefix>/share/inkscape/…` (it
  appends its own name under share) — stage `$SRC/share/*` one level deeper.
- **Deterministic profile**: a fresh profile defaults `showwelcome=1` and
  `on_activate` blocks in the welcome-screen modal loop. Ship
  `fixtures/inkscape-prefs.xml` (welcome/splash off) to BOTH the wasm FS and
  the native golden run (INKSCAPE_PROFILE_DIR) so neither side can diverge.
- Diagnostics that worked: node `--cpu-prof` writes nothing on SIGTERM —
  use a CDP client (`--inspect-brk` + Profiler.start/stop over WebSocket)
  to sample a spinning wasm stack, then resolve wasm-function[N] via
  `wasm-objdump -x`.

## Leg D/E — GUI + harness (T6/T7 gates, 2026-10-13)

Both gates green. T6: boot stages + canvas paint (toolDark=3026,
bodyLight=5332). T7: F4 → canvas drag → `<rect>` in doc → real
`document-save` → export PNG **pixelmatch 0/480000 (0.000%)** vs a native
export of the same saved document.

### The renderer crash (root cause + fix)

The browser renderer SEGV'd ~5.5s after boot with **no user input**. Chain:
broadway/GTK bookmarks a `GPollFileMonitor` (5s poll timeout) → its GTask
completes → **`g_task_run_in_thread` re-completes tasks that already
completed during the inline thread-pool push** (our
`gthreadpool-inline-push` leg-C patch) → every GTask callback runs twice →
monitor freed twice + duplicated timeout GSource → `g_source_unref` on a
dangling source → wasm OOB (clean RuntimeError in node, renderer SEGV in
Chromium). Fix: `patches/glib/gtask-no-double-complete-emscripten.patch` —
skip the re-complete when `thread_complete && !thread_cancelled` (wasm-
guarded). Node time-repro (real-time 16ms frame pumping — instant pumping
hides time-based paths) survives 25s; headless shell 60s incl. a click.

### The document-save hang (root cause + fix)

`document-save` spun at 100% CPU between `sp_file_save_document` entry and
`file_save` entry. Breadcrumbs showed `fn=(null)`: the desktop document
had **no filename**. Why: the `file-open` app action
(`actions-file.cpp::file_open`) opens the doc as a *second, invisible*
document and nulls the active desktop — the canvas kept showing the
untitled template doc, so Save correctly took the SaveAs-dialog branch,
and **constructing a `Gtk::FileChooserDialog` spins forever in wasm**
(hangs before `dialog_run`'s blocking iteration is even reached — no
surface is created). Dragging/exporting "worked" because both target the
desktop/app-active doc — the template — which is why earlier save tests
were an illusion (they read back bytes the test itself had written).

Fix: `patches/inkscape/file-open-swap-emscripten.patch` — under
`__EMSCRIPTEN__`, `file_open` swaps the opened document into the active
window via the stock `InkscapeApplication::document_swap` (one window on
broadway, desktop doc == opened file, filename intact) →
`sp_file_save_document` takes the plain-write branch and returns.
Harness Save button no longer fires `document-save-as` with no doc open
(the SaveAs dialog hang is unfixed and inherent — see hazards).

### Leg D/E quirks worth keeping

- **F4 needs a focused window**: the broadway daemon drops key events
  until a button press focuses a window — click the canvas *before*
  pressing F4 (t7.spec does click → F4 → drag, with a verify-and-retry in
  case the keypress lands early).
- Keymap loads via `inkscape.xml` fallback; `default.xml` is a
  CMake-install rename absent when staging from the source tree.
- `parse_actions` only resolves *app* actions; `document-save` /
  `tool-switch` are *window* actions — the action-hook patch now falls
  back to `_active_window->lookup_action` under `__EMSCRIPTEN__`.
- `dialog_run` (ui/dialog-run.cpp) blocks in
  `main_context->iteration(true)` — **any** modal dialog hangs wasm
  (Filechooser construction spins even before that). Everything in the
  harness avoids modal paths.
- Emscripten `ENV` is empty: host env vars never reach `getenv`.
- Emscripten mutexes/conds are no-ops (no -pthread); gdb attach to node
  is blocked by yama ptrace_scope — use breadcrumbs + wasm-objdump maps
  (`wasm-d.txt` disasm offsets match stack addresses directly), or
  Chromium `--enable-logging=stderr` for native backtraces.
- `db.get(".svg")` returning null is *stock* behavior (dict is keyed by
  module id, not extension) — `Extension::save` autodetects the output
  module from the filename; not a wasm bug.

## Post-port: IDBFS persistence (2026-10-13)

- `-lidbfs.js` appended to the inkscape link flags (JS glue only, no wasm
  change) — without it `FS.filesystems.IDBFS` is undefined. Relink needed
  the usual binary-delete (ninja can't see `-l` flag changes).
- `harness/loader.js` mounts `/home/web_user/documents` on IDBFS:
  `syncfs(true)` on boot restores the last session, `syncfs(false)` after
  every write (`window.__fs_flushed` promise; syncfs(false) snapshots the
  whole mount, so awaiting the latest flush covers earlier writes).
  docPath restore: exactly one persisted `.svg` resumes the session;
  multiple leaves Save disabled until re-Open (v1 behavior).
- Scratch paths (`t7`'s `/home/web_user/dbg.svg`) stay outside the mount —
  session-only by design. prefs stay in the packaged FS (`/home/web_user`
  root), unshadowed by the mount.
- T7 now ends with a hard reload: saved doc + restored `__doc_path` must
  survive a fresh boot (IndexedDB-backed).

## Leg F — icons, zero-error boot & harness polish (T8 gate, 2026-10-16)

- **Icons (`packages/encode-icons.py`)**: wasm `gdk-pixbuf` has no `librsvg`,
  so `GtkIconTheme` ignored all `.svg` icon files and fell back to 1x1
  `image-missing.png`. Pre-encoding 2,513 symbolic SVGs via host
  `/usr/bin/gtk-encode-symbolic-svg` to `.symbolic.png` (which GTK3's
  built-in `gtk_icon_info_load_symbolic_png` recolors in C with no SVG loader)
  and rasterizing 1,701 scalable SVGs via host `libgdk_pixbuf-2.0.so.0` to
  `.png`, plus setting `iconTheme="multicolor" symbolicIcons="1"` in
  `inkscape-prefs.xml`, restores all toolbox/toolbar/widget icons (T8:
  12/12 left toolbox slots, 16/16 top toolbar slots).
- **Zero-error boot**:
  - `packages/pthread_supp.c`: dropped leftover `console.warn`/`console.trace`
    in `pthread_create`.
  - `patches/gtk3/clean-boot-emscripten.patch`: null-check `g_module_open(NULL, 0)`
    in `_gtk_module_has_mixed_deps`; drop `.svg` primary URLs from Adwaita
    CSS `-gtk-icon-source` rules so GTK uses the `.symbolic.png` GResources
    directly without logging pixbuf warnings.
  - `patches/inkscape/clean-boot-emscripten.patch`: return
    `"/inkscape/bin/inkscape"` from `get_program_name()` under `__EMSCRIPTEN__`;
    skip empty key strings in `Shortcuts::_read` and `Shortcuts::add_shortcut`
    before constructing `Gtk::AccelKey("")`.
  - `packages/inkscape.sh`: stage `keys/default.xml` and a valid
    `cphistory.xml` (`<cphistory><operations/><params/></cphistory>` —
    `CPHistoryXML` assumes both child nodes exist when the file is present).
- **Harness UX**: offset `body > canvas` by `52px` (`#toolbar` + `#stagebar`)
  and translate `ev.pageY` in `window.getPositionsFromEvent` so the menu bar
  is unoccluded while canvas click/drag coordinates stay exact; `Save` on an
  unopened canvas exports to `/home/web_user/documents/drawing.svg`.
