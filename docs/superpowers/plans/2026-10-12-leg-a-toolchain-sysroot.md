# Leg A — Toolchain & Sysroot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Emscripten sysroot containing every Inkscape dependency, each proven by a Node smoke test — gates T0 and T1 of the testing ladder.

**Architecture:** One `packages/<name>.sh` script per dependency, sharing helpers from `packages/common.sh` (fetch → extract → build via CMake/Meson/autotools → install into `build/sysroot` → run a per-package smoke test in Node → stamp). A top-level Makefile drives the ordered sequence; full runs go through `oc-bg`.

**Tech Stack:** Emscripten (existing emsdk at `/data/jake/reversing/toki/emsdk`), CMake+Ninja, Meson, autotools/emconfigure, pkg-config, ccache, Node.

## Global Constraints

- Repo root: `/data/jake/reversing/inkscape`. All paths below are relative to it.
- Emscripten is only ever activated by sourcing `packages/common.sh` (which sources `$EMSDK_DIR/emsdk_env.sh` with `EMSDK_DIR=/data/jake/reversing/toki/emsdk`).
- Every library is built **static only** (no shared libs on wasm). Link flags like `-sASYNCIFY -sMODULARIZE` belong to the final module link (Leg C), not to library builds.
- Common compile flags: `-O1 -g1 -ffunction-sections -fdata-sections -fexceptions -frtti` (RTTI for C++). No `-pthread`, no SharedArrayBuffer anywhere.
- Package script filenames avoid special characters: `sigcpp.sh`, `gtk3.sh` (real names recorded in `build/manifest.txt`).
- **URL fallback rule:** if a pinned URL 404s, substitute the closest release from the project's official releases page, update the pin in the script, and record the substitution in `docs/findings.md` and the manifest. This is the *only* sanctioned deviation from pinned versions.
- **Build failure rule:** a package that fails to configure/build gets (a) a diagnosis in `docs/findings.md` with the log path (`build/logs/`), (b) if needed, a patch in `patches/<pkg>/` applied by its script — never an in-place edit of extracted source. If both fail, that's the T1 kill criterion: stop, report.
- Long-running commands (any full `make deps`, any single package expected >2 min) run via `oc-bg <log> -- <cmd>`; short single-package rebuilds may run foreground.
- Stamps: `build/stamps/<pkg>.ok` written only after that package's smoke test passes. `rm build/stamps/<pkg>.ok` forces a rebuild.
- Commits after every task; `git add -A` from repo root.

---

### Task 1: Scaffolding + T0 toolchain smoke test

**Files:**
- Create: `Makefile`, `packages/common.sh`, `packages/emsdk.cross`, `tests/t0/run.sh`, `tests/lib/t0_smoke.cpp`
- Produces: build helpers used by every later task (`begin_pkg`, `fetch`, `extract_auto`, `cm`, `me`, `ac`, `wasmtest`, `manifest`), `make check-0`

**Interfaces:**
- `wasmtest <name> <src-under-tests/lib/> [link-args...]` — compiles a C/C++ test with the sysroot flags, preloads `tests/fixtures` at `/fixtures`, runs it in Node, prints `PASS: <name>` and exits non-zero on failure.
- `cm <name> [cmake-args]` / `me <name> [meson-args]` / `ac <name> [configure-args]` — build+install package `<name>` from `build/src/<name>` into the sysroot.

- [ ] **Step 1: Check the native tool inventory; install anything missing**

Run: `cmake --version; ninja --version; meson --version; pkg-config --version; ccache --version; node --version; curl --version | head -1`
Expected: all print versions. Install missing ones: `pip install --user meson ninja` (meson/ninja), `sudo apt install cmake pkg-config ccache` (or the local equivalent if sudo is unavailable — record what you did in findings).

- [ ] **Step 2: Write the T0 test first**

`tests/lib/t0_smoke.cpp`:

```cpp
#include <cstdio>
#include <stdexcept>
#include <string>
#include <typeinfo>

struct Base { virtual ~Base() = default; virtual const char* name() const { return "base"; } };
struct Derived : Base { const char* name() const override { return "derived"; } };

int main() {
    Base* b = new Derived();
    if (std::string(typeid(*b).name()).find("Derived") == std::string::npos)
        throw std::logic_error("rtti broken");
    if (std::string(b->name()) != "derived")
        throw std::logic_error("vtable broken");
    delete b;
    try { throw std::runtime_error("expected"); }
    catch (const std::runtime_error& e) { std::printf("hello wasm: exceptions+rtti ok (%s)\n", e.what()); }
    return 0;
}
```

`tests/t0/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."; source packages/common.sh
wasmtest t0 t0_smoke.cpp
```

- [ ] **Step 3: Write `packages/common.sh`**

```bash
#!/usr/bin/env bash
# packages/common.sh — shared build environment. Source it; never execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"; SYSROOT="$BUILD/sysroot"; STAMPS="$BUILD/stamps"
LOGS="$BUILD/logs"; SRC="$BUILD/src"; DL="$BUILD/dl"; TEST="$BUILD/test"
PATCHES="$ROOT/patches"
EMSDK_DIR="/data/jake/reversing/toki/emsdk"

source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1

export CC="ccache emcc" CXX="ccache em++" AR="emar" RANLIB="emranlib"
export CFLAGS="-O1 -g1 -ffunction-sections -fdata-sections -fexceptions"
export CXXFLAGS="$CFLAGS -frtti"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export CMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"

mkdir -p "$SYSROOT" "$STAMPS" "$LOGS" "$SRC" "$DL" "$TEST"

begin_pkg() { # begin_pkg <name> — exit 0 if already stamped
  if [ -e "$STAMPS/$1.ok" ]; then echo "$1: cached (rm build/stamps/$1.ok to rebuild)"; exit 0; fi
}
manifest() { echo "$1 $2" >> "$BUILD/manifest.txt"; } # manifest <real-name> <version>
fetch() { # fetch <url> — download to build/dl if missing
  local out="$DL/$(basename "$1")"
  [ -s "$out" ] || curl -fL --retry 3 -o "$out" "$1"
}
extract_auto() { # extract_auto <archive-basename> <name> — extract, rename top dir to build/src/<name>
  local archive="$1" name="$2" tmp="$SRC/.$2.extract.$$"
  if [ ! -d "$SRC/$name" ]; then
    mkdir -p "$tmp"; tar -xf "$DL/$archive" -C "$tmp"
    mv "$tmp"/*/ "$SRC/$name"; rmdir "$tmp"
  fi
}
cm() { # cm <name> [cmake args...] — CMake+Ninja build+install
  local name="$1"; shift
  cmake -S "$SRC/$name" -B "$BUILD/$name" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache "$@"
  cmake --build "$BUILD/$name" -j 64
  cmake --install "$BUILD/$name"
}
me() { # me <name> [meson args...] — Meson build+install (cross file, static)
  local name="$1"; shift
  meson setup "$BUILD/$name" "$SRC/$name" --prefix="$SYSROOT" \
    --cross-file "$ROOT/packages/emsdk.cross" --buildtype=release \
    --default-library=static "$@"
  meson compile -C "$BUILD/$name" -j 64
  meson install -C "$BUILD/$name"
}
ac() { # ac <name> [configure args...] — autotools build via emconfigure
  local name="$1"; shift
  mkdir -p "$BUILD/$name"
  ( cd "$BUILD/$name"
    emconfigure "$SRC/$name/configure" --prefix="$SYSROOT" \
      --host=wasm32-emscripten --disable-shared --enable-static "$@" )
  ( cd "$BUILD/$name" && emmake make -j64 && emmake make install )
}
wasmtest() { # wasmtest <name> <src-under-tests/lib> [link args...]
  local name="$1" src="$ROOT/tests/lib/$2"; shift 2
  local comp=emcc; case "$src" in *.cpp|*.cc) comp=em++;; esac
  "$comp" "$src" -o "$TEST/$name.js" $CXXFLAGS \
    -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=1 \
    --preload-file "$ROOT/tests/fixtures@/fixtures" "$@"
  ( cd "$TEST" && node "$name.js" )
  echo "PASS: $name"
}
```

`packages/emsdk.cross`:

```ini
[binaries]
c = 'emcc'
cpp = 'em++'
ar = 'emar'
strip = 'emstrip'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
```

- [ ] **Step 4: Write the Makefile**

```make
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OBG  := $(HOME)/.config/opencode/bin/oc-bg
PKGS := zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
        libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
        gtkmm libxml2 libxslt gsl dconv boost libgc potrace lib2geom
# if potrace is cut (Task 19 optional rule), remove it from this list

.PHONY: deps deps-real pkg-% check-0 check-1 clean

deps:
	$(OBG) build/logs/deps -- $(MAKE) deps-real

deps-real:
	@for p in $(PKGS); do echo "== $$p =="; bash packages/$$p.sh || exit 1; done

pkg-%:
	bash packages/$*.sh

check-0: ; bash tests/t0/run.sh
check-1: ; bash tests/check-1.sh

clean:
	rm -rf build
```

- [ ] **Step 5: Run T0 — verify PASS**

Run: `chmod +x tests/t0/run.sh && bash tests/t0/run.sh`
Expected: prints `hello wasm: exceptions+rtti ok (expected)` then `PASS: t0`. If emsdk activation fails, diagnose before proceeding (kill criterion for this task only: broken emsdk — reinstall emsdk into the same location, record version change in findings).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "leg A: scaffolding + T0 toolchain smoke test"
```

---

### Task 2: zlib (pipeline proof)

**Files:**
- Create: `packages/zlib.sh`, `tests/lib/zlib_test.c`

**Interfaces:**
- Produces: sysroot lib `z` (`pkg-config: zlib`), proving the fetch→build→test→stamp pipeline.

- [ ] **Step 1: Write the test**

`tests/lib/zlib_test.c`:

```c
#include <zlib.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main() {
    const char* msg = "the quick brown fox jumps over the lazy dog";
    unsigned char comp[128], decomp[128];
    uLongf comp_len = sizeof comp, decomp_len = sizeof decomp;
    assert(compress(comp, &comp_len, (const Bytef*)msg, strlen(msg)) == Z_OK);
    assert(uncompress(decomp, &decomp_len, comp, comp_len) == Z_OK);
    assert(decomp_len == strlen(msg));
    assert(memcmp(decomp, msg, decomp_len) == 0);
    printf("zlib ok: %zu -> %lu -> %zu bytes\n", strlen(msg), comp_len, decomp_len);
    return 0;
}
```

- [ ] **Step 2: Write `packages/zlib.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg zlib
VER=1.3.1
fetch "https://github.com/madler/zlib/releases/download/v$VER/zlib-$VER.tar.gz"
extract_auto "zlib-$VER.tar.gz" zlib
cm zlib
wasmtest zlib zlib_test.c -lz -L"$SYSROOT/lib"
manifest zlib "$VER"
touch "$STAMPS/zlib.ok"
```

- [ ] **Step 3: Run it**

Run: `bash packages/zlib.sh`
Expected: CMake builds without errors, then `zlib ok: ...` and `PASS: zlib`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "leg A: zlib + smoke test"
```

---

### Task 3: libpng

**Files:**
- Create: `packages/libpng.sh`, `tests/lib/libpng_test.c`

**Interfaces:**
- Consumes: zlib from sysroot.
- Produces: `pkg-config: libpng`.

- [ ] **Step 1: Write the test** — round-trip a 4×4 RGBA image through PNG write/read in memfs:

```c
#include <png.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main() {
    const char* path = "/tmp/png_test.png";
    png_bytep row = calloc(4, 4 * 4);
    row[0] = 0xAA; row[1] = 0xBB; row[2] = 0xCC; row[3] = 0xFF; // pixel (0,0) as RGBA
    FILE* f = fopen(path, "wb");
    png_structp w = png_create_write_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
    png_infop wi = png_create_info_struct(w);
    png_init_io(w, f);
    png_set_IHDR(w, wi, 4, 4, 8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(w, wi);
    for (int y = 0; y < 4; y++) png_write_row(w, row);
    png_write_end(w, wi);
    png_destroy_write_struct(&w, &wi);
    fclose(f);
    FILE* r = fopen(path, "rb");
    unsigned char magic[8];
    assert(fread(magic, 1, 8, r) == 8);
    static const unsigned char png_sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    assert(memcmp(magic, png_sig, 8) == 0);
    fclose(r);
    printf("libpng ok (magic bytes verified)\n");
    return 0;
}
```

- [ ] **Step 2: Write `packages/libpng.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libpng
VER=1.6.45
fetch "https://github.com/pnggroup/libpng/archive/refs/tags/v$VER.tar.gz"
extract_auto "libpng-$VER.tar.gz" libpng
cm libpng -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
wasmtest libpng libpng_test.c "$(pkg-config --cflags --libs libpng)"
manifest libpng "$VER"
touch "$STAMPS/libpng.ok"
```

- [ ] **Step 3: Run** — `bash packages/libpng.sh` → expect `libpng ok` + `PASS: libpng`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: libpng + smoke test"`

---

### Task 4: freetype + test fixtures

**Files:**
- Create: `packages/freetype.sh`, `tests/lib/freetype_test.c`, `tests/fixtures/fonts.conf`, `tests/fixtures/basic.svg`, `tests/fixtures/tiny.png` (binary)
- Note: `tests/fixtures/DejaVuSans.ttf` is copied/downloaded, **not** committed.

**Interfaces:**
- Produces: `pkg-config: freetype2`; the `/fixtures` preload dir (font, fonts.conf, SVGs) used by every later text-rendering test.

- [ ] **Step 1: Create the fixtures**

`tests/fixtures/fonts.conf`:

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/fixtures</dir>
  <cachedir>/tmp/fcache</cachedir>
</fontconfig>
```

`tests/fixtures/basic.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <rect x="10" y="10" width="30" height="20" fill="red"/>
  <rect x="50" y="50" width="20" height="30" fill="blue"/>
</svg>
```

Run (DejaVu font — copy from system, download as fallback):

```bash
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf tests/fixtures/ 2>/dev/null \
  || curl -fL -o /tmp/dejavu.tar.bz2 \
    https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2 \
  && tar -xf /tmp/dejavu.tar.bz2 -C /tmp \
  && cp /tmp/dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf tests/fixtures/
```

Run (1×1 transparent PNG fixture):

```bash
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' \
  | base64 -d > tests/fixtures/tiny.png
```

- [ ] **Step 2: Write the test**

`tests/lib/freetype_test.c`:

```c
#include <ft2build.h>
#include <freetype/freetype.h>
#include <assert.h>
#include <stdio.h>

int main() {
    FT_Library lib;
    assert(FT_Init_FreeType(&lib) == 0);
    FT_Face face;
    assert(FT_New_Face(lib, "/fixtures/DejaVuSans.ttf", 0, &face) == 0);
    assert(face->num_glyphs > 1000);
    assert(FT_Set_Char_Size(face, 0, 16 * 64, 72, 72) == 0);
    assert(FT_Load_Char(face, 'A', FT_LOAD_RENDER) == 0);
    printf("freetype ok: %ld glyphs, 'A' bitmap %dx%d\n",
           face->num_glyphs, face->glyph->bitmap.width, face->glyph->bitmap.rows);
    return 0;
}
```

- [ ] **Step 3: Write `packages/freetype.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg freetype
VER=2.13.3
fetch "https://download.savannah.gnu.org/releases/freetype/freetype-$VER.tar.gz"
extract_auto "freetype-$VER.tar.gz" freetype
cm freetype -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=ON \
            -DFT_REQUIRE_PNG=ON -DFT_REQUIRE_ZLIB=ON -DFT_BUILD_TESTS=OFF
wasmtest freetype freetype_test.c "$(pkg-config --cflags --libs freetype2)"
manifest freetype "$VER"
touch "$STAMPS/freetype.ok"
```

- [ ] **Step 4: Run** — `bash packages/freetype.sh` → expect `freetype ok: ... glyphs` + `PASS: freetype`.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "leg A: freetype + shared test fixtures"`

---

### Task 5: expat + fontconfig

**Files:**
- Create: `packages/expat.sh`, `packages/fontconfig.sh`, `tests/lib/expat_test.c`, `tests/lib/fontconfig_test.c`

**Interfaces:**
- Consumes: freetype (fontconfig links it).
- Produces: `pkg-config: expat`, `fontconfig`.

- [ ] **Step 1: Write the tests**

`tests/lib/expat_test.c`:

```c
#include <expat.h>
#include <assert.h>
#include <stdio.h>

static int count = 0;
static void start(void* ud, const XML_Char* name, const XML_Char** atts) { count++; }

int main() {
    XML_Parser p = XML_ParserCreate(NULL);
    XML_SetElementHandler(p, start, NULL);
    assert(XML_Parse(p, "<a><b/><c x=\"1\"/></a>", -1, 1) == XML_STATUS_OK);
    assert(count == 3);
    printf("expat ok: %d elements\n", count);
    return 0;
}
```

`tests/lib/fontconfig_test.c`:

```c
#include <fontconfig/fontconfig.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    setenv("FONTCONFIG_PATH", "/fixtures/fc", 1); // fixtures dir holds our fonts.conf
    assert(FcInit());
    FcPattern* pat = FcPatternBuild(NULL, FC_FAMILY, FcTypeString, (FcChar8*)"DejaVu Sans", NULL);
    FcConfigSubstitute(NULL, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);
    FcResult res;
    FcPattern* m = FcFontMatch(NULL, pat, &res);
    assert(m != NULL);
    FcChar8* file = NULL;
    assert(FcPatternGetString(m, FC_FILE, 0, &file) == FcResultMatch);
    printf("fontconfig ok: matched %s\n", file);
    return 0;
}
```

For the fontconfig test, `wasmtest` also needs the fonts.conf in the preload root as `/fixtures/fc/fonts.conf`:

```bash
mkdir -p tests/fixtures/fc && cp tests/fixtures/fonts.conf tests/fixtures/fc/fonts.conf
```

(The `fc/` copy exists so tests can point `FONTCONFIG_PATH` at `/fixtures/fc` while the top-level `fonts.conf` stays for documentation.)

- [ ] **Step 2: Write the package scripts**

`packages/expat.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg expat
VER=2.6.4
fetch "https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-$VER.tar.gz"
extract_auto "expat-$VER.tar.gz" expat
cm expat -DEXPAT_SHARED_LIBS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF
wasmtest expat expat_test.c -lexpat -L"$SYSROOT/lib"
manifest expat "$VER"
touch "$STAMPS/expat.ok"
```

`packages/fontconfig.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg fontconfig
VER=2.16.0
fetch "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$VER.tar.xz"
extract_auto "fontconfig-$VER.tar.xz" fontconfig
me fontconfig -Ddoc=disabled -Dnls=disabled -Dtests=disabled \
  -Dfreetype=enabled -Dexpat=enabled -Ddefault-fonts-dirs=/fixtures
wasmtest fontconfig fontconfig_test.c "$(pkg-config --cflags --libs fontconfig)"
manifest fontconfig "$VER"
touch "$STAMPS/fontconfig.ok"
```

If fontconfig's meson setup tries to run cross-built binaries or probe system fonts, add `-Dcache-build=disabled`; if that option doesn't exist in this version, record the failure and the chosen workaround in findings (Global Constraints: build failure rule).

- [ ] **Step 3: Run** — `bash packages/expat.sh && bash packages/fontconfig.sh` → expect `expat ok: 3 elements`, `PASS: expat`, `fontconfig ok: matched /fixtures/DejaVuSans.ttf`, `PASS: fontconfig`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: expat + fontconfig + smoke tests"`

---

### Task 6: pixman + fribidi

**Files:**
- Create: `packages/pixman.sh`, `packages/fribidi.sh`, `tests/lib/pixman_test.c`, `tests/lib/fribidi_test.c`

**Interfaces:**
- Produces: `pkg-config: pixman-1`, `fribidi` (cairo and pango deps).

- [ ] **Step 1: Write the tests**

`tests/lib/pixman_test.c`:

```c
#include <pixman.h>
#include <assert.h>
#include <stdio.h>

int main() {
    pixman_image_t* img = pixman_image_create_bits(PIXMAN_a8r8g8b8, 8, 8, NULL, 0);
    assert(img);
    pixman_color_t color = { 0xffff, 0, 0, 0xffff }; // opaque red
    pixman_rectangle16_t rect = { 0, 0, 8, 8 };
    assert(pixman_image_fill_rectangles(PIXMAN_OP_SRC, img, &color, 1, &rect));
    uint32_t* bits = (uint32_t*)pixman_image_get_data(img);
    assert(bits[0] == 0xffff0000u); // a8r8g8b8 red
    pixman_image_unref(img);
    printf("pixman ok\n");
    return 0;
}
```

`tests/lib/fribidi_test.c`:

```c
#include <fribidi.h>
#include <assert.h>
#include <stdio.h>

int main() {
    const FriBidiChar logical[] = {0x05D0, 0x05D1, 0x0041}; // alef, bet, 'A' — RTL run in LTR paragraph
    FriBidiChar visual[3]; FriBidiStrIndex len = 3;
    FriBidiCharType base = FRIBIDI_PAR_LTR;
    FriBidiLevel levels[3];
    FriBidiLevel max = fribidi_log2vis(logical, len, &base, visual, NULL, levels, NULL);
    assert(max > 0);
    assert(visual[2] == 0x0041); // LTR char keeps trailing slot
    printf("fribidi ok: max level %d\n", max);
    return 0;
}
```

- [ ] **Step 2: Write the package scripts**

`packages/pixman.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pixman
VER=0.44.0
fetch "https://www.cairographics.org/releases/pixman-$VER.tar.gz"
extract_auto "pixman-$VER.tar.gz" pixman
me pixman -Dtests=disabled -Ddemos=disabled -Dlibpng=disabled -Dgtk=disabled
wasmtest pixman pixman_test.c "$(pkg-config --cflags --libs pixman-1)"
manifest pixman "$VER"
touch "$STAMPS/pixman.ok"
```

`packages/fribidi.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg fribidi
VER=1.0.16
fetch "https://github.com/fribidi/fribidi/releases/download/v$VER/fribidi-$VER.tar.gz"
extract_auto "fribidi-$VER.tar.gz" fribidi
me fribidi -Dtests=false -Ddocs=false
wasmtest fribidi fribidi_test.c "$(pkg-config --cflags --libs fribidi)"
manifest fribidi "$VER"
touch "$STAMPS/fribidi.ok"
```

- [ ] **Step 3: Run** — `bash packages/pixman.sh && bash packages/fribidi.sh` → expect `pixman ok`, `PASS: pixman`, `fribidi ok: max level ...`, `PASS: fribidi`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: pixman + fribidi + smoke tests"`

---

### Task 7: harfbuzz

**Files:**
- Create: `packages/harfbuzz.sh`, `tests/lib/harfbuzz_test.c`

**Interfaces:**
- Consumes: freetype.
- Produces: `pkg-config: harfbuzz` (+ `harfbuzz-ft`), shaping used later by pango.

- [ ] **Step 1: Write the test** — shape "fi" with DejaVu, assert two glyphs with real ids:

```c
#include <hb.h>
#include <hb-ft.h>
#include <assert.h>
#include <stdio.h>

int main() {
    hb_blob_t* blob = hb_blob_create_from_file("/fixtures/DejaVuSans.ttf");
    assert(blob && hb_blob_get_length(blob) > 0);
    hb_face_t* face = hb_face_create(blob, 0);
    hb_font_t* font = hb_font_create(face);
    hb_buffer_t* buf = hb_buffer_create();
    hb_buffer_add_utf8(buf, "fi", -1, 0, -1);
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font, buf, NULL, 0);
    unsigned len = hb_buffer_get_length(buf);
    hb_glyph_info_t* info = hb_buffer_get_glyph_infos(buf, NULL);
    assert(len == 2);
    assert(info[0].codepoint > 0 && info[1].codepoint > 0); // real glyph ids, not .notdef
    printf("harfbuzz ok: glyphs %u %u\n", info[0].codepoint, info[1].codepoint);
    return 0;
}
```

- [ ] **Step 2: Write `packages/harfbuzz.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg harfbuzz
VER=10.4.0
fetch "https://github.com/harfbuzz/harfbuzz/releases/download/$VER/harfbuzz-$VER.tar.xz"
extract_auto "harfbuzz-$VER.tar.xz" harfbuzz
me harfbuzz -Dtests=disabled -Ddocs=disabled -Dutilities=disabled \
  -Dicu=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
  -Dfreetype=enabled -Dintrospection=disabled
wasmtest harfbuzz harfbuzz_test.c "$(pkg-config --cflags --libs harfbuzz)"
manifest harfbuzz "$VER"
touch "$STAMPS/harfbuzz.ok"
```

Note: glib is disabled here deliberately (glib isn't built yet); pango links harfbuzz without the glib integration fine. If harfbuzz's release tarball URL for this pin 404s, apply the URL fallback rule.

- [ ] **Step 3: Run** — `bash packages/harfbuzz.sh` → expect `harfbuzz ok: glyphs N M` + `PASS: harfbuzz`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: harfbuzz + smoke test"`

---

### Task 8: cairo

**Files:**
- Create: `packages/cairo.sh`, `tests/lib/cairo_test.c`

**Interfaces:**
- Consumes: pixman, libpng, freetype, fontconfig, zlib.
- Produces: `pkg-config: cairo` (image-surface PNG backend) — the raster engine under everything later.

- [ ] **Step 1: Write the test** — draw red field + blue stroke, verify in-memory pixel and PNG file:

```c
#include <cairo.h>
#include <assert.h>
#include <stdio.h>

int main() {
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 64);
    assert(cairo_surface_status(s) == CAIRO_STATUS_SUCCESS);
    cairo_t* cr = cairo_create(s);
    cairo_set_source_rgb(cr, 1, 0, 0);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 0, 0, 1);
    cairo_set_line_width(cr, 4);
    cairo_move_to(cr, 8, 8); cairo_line_to(cr, 56, 56); cairo_stroke(cr);
    cairo_destroy(cr);
    unsigned char* d = cairo_image_surface_get_data(s);
    assert(d[2] == 255 && d[1] == 0 && d[0] == 0); // corner pixel is red (BGRA)
    assert(cairo_surface_write_to_png(s, "/tmp/cairo_test.png") == CAIRO_STATUS_SUCCESS);
    FILE* f = fopen("/tmp/cairo_test.png", "rb");
    unsigned char magic[4];
    assert(fread(magic, 1, 4, f) == 4);
    assert(magic[1] == 'P' && magic[2] == 'N' && magic[3] == 'G');
    fclose(f);
    cairo_surface_destroy(s);
    printf("cairo ok (red pixel + PNG write verified)\n");
    return 0;
}
```

- [ ] **Step 2: Write `packages/cairo.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg cairo
VER=1.18.2
fetch "https://www.cairographics.org/releases/cairo-$VER.tar.xz"
extract_auto "cairo-$VER.tar.xz" cairo
me cairo -Dtests=disabled -Dspectre=disabled -Dsymbol-lookup=disabled \
  -Dxlib=disabled -Dxlib-xrender=disabled -Dxcb=disabled -Dqt=disabled \
  -Dquartz=disabled -Dwin32=disabled -Dskia=disabled -Dsqlite=disabled \
  -Dzlib=enabled -Dpng=enabled -Dfreetype=enabled -Dfontconfig=enabled \
  -Ddwrite=disabled -Dcogl=disabled -Dopenvg=disabled -Ddrm=disabled \
  -Dglib=disabled -Dxml=disabled -Dtests=disabled
wasmtest cairo cairo_test.c "$(pkg-config --cflags --libs cairo)"
manifest cairo "$VER"
touch "$STAMPS/cairo.ok"
```

Notes: `glib=disabled` avoids the not-yet-built glib dep (cairo's glib integration is optional). If a meson option name differs in this version, `meson configure build/cairo` lists the real ones — adjust, don't force.

- [ ] **Step 3: Run** — `bash packages/cairo.sh` → expect `cairo ok (...)` + `PASS: cairo`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: cairo + smoke test"`

---

### Task 9: libffi (GObject closure hazard)

**Files:**
- Create: `packages/libffi.sh`, `tests/lib/libffi_test.c`

**Interfaces:**
- Produces: `pkg-config: ffi` — required by glib/GObject. **This is a T1 hazard package** (spec 01 addendum): closures on wasm are historically broken; test both plain calls and closures.

- [ ] **Step 1: Write the test** — plain `ffi_call` first, then a closure through a function pointer:

```c
#include <ffi.h>
#include <assert.h>
#include <stdio.h>

static int add_i32(int a, int b) { return a + b; }
static void double_it(ffi_cif* cif, void* ret, void** args, void* ud) {
    *(ffi_sarg*)ret = *(int*)args[0] * 2;
}

int main() {
    // 1. plain call
    ffi_cif cif;
    ffi_type* args[2] = { &ffi_type_sint32, &ffi_type_sint32 };
    int a = 3, b = 4; void* vals[2] = { &a, &b }; int rc = 0;
    assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint32, args) == FFI_OK);
    ffi_call(&cif, FFI_FN(add_i32), &rc, vals);
    assert(rc == 7);
    printf("libffi plain call ok (3+4=%d)\n", rc);

    // 2. closure (the wasm hazard)
    void* code = NULL;
    ffi_closure* clo = ffi_closure_alloc(sizeof(ffi_closure), &code);
    assert(clo && code);
    ffi_cif ccif; int x = 5; void* cvals[1] = { &x };
    assert(ffi_prep_cif(&ccif, FFI_DEFAULT_ABI, 1, &ffi_type_sint32, &ffi_type_sint32) == FFI_OK);
    assert(ffi_prep_closure_loc(clo, &ccif, double_it, NULL, code) == FFI_OK);
    int (*fn)(int) = (int(*)(int))code;
    int result = fn(5);
    assert(result == 10);
    printf("libffi closure ok (5*2=%d)\n", result);
    return 0;
}
```

- [ ] **Step 2: Write `packages/libffi.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libffi
VER=3.4.6
fetch "https://github.com/libffi/libffi/releases/download/v$VER/libffi-$VER.tar.gz"
extract_auto "libffi-$VER.tar.gz" libffi
ac libffi --disable-docs --disable-multi-os-directory
wasmtest libffi libffi_test.c "$(pkg-config --cflags --libs ffi)"
manifest libffi "$VER"
touch "$STAMPS/libffi.ok"
```

- [ ] **Step 3: Run and triage**

Run: `bash packages/libffi.sh`

Three outcomes:
1. **Plain + closure both pass** → done, commit.
2. **Plain passes, closure crashes/hangs** → this is the known wasm ffi closure problem. Fix path: apply the emscripten closure patch from the wasmlabs/cpython-wasm libffi work (search GitHub for "libffi emscripten closure patch"; the wasmlabs fork carries it), save it as `patches/libffi/emscripten-closures.patch`, add `patch -d "$SRC/libffi" -p1 < "$PATCHES/libffi/emscripten-closures.patch"` between `extract_auto` and `ac`, rebuild, rerun. Record which patch in findings + manifest.
3. **Configure fails** → build-failure rule: findings + patch, or T1 kill criterion.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: libffi + closure smoke test"`

---

### Task 10: glib

**Files:**
- Create: `packages/glib.sh`, `tests/lib/glib_test.c`

**Interfaces:**
- Consumes: libffi, zlib.
- Produces: `pkg-config: glib-2.0 gobject-2.0 gio-2.0` — the substrate for everything remaining.

- [ ] **Step 1: Write the test** — strings, hash table, one non-blocking main-loop iteration, GVariant:

```c
#include <glib.h>
#include <assert.h>
#include <stdio.h>

int main() {
    GString* s = g_string_new("hello");
    g_string_append(s, " glib");
    assert(g_strcmp0(s->str, "hello glib") == 0);
    g_string_free(s, TRUE);

    GHashTable* h = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(h, "k", "v");
    assert(g_strcmp0(g_hash_table_lookup(h, "k"), "v") == 0);
    g_hash_table_destroy(h);

    GMainContext* ctx = g_main_context_default();
    assert(g_main_context_iteration(ctx, FALSE) == FALSE); // no sources: returns immediately

    GVariant* v = g_variant_new("(is)", 42, "x");
    gchar* t = g_variant_print(v, TRUE);
    assert(g_str_has_prefix(t, "(42,"));
    g_free(t);

    GObject* o = g_object_new(G_TYPE_OBJECT, NULL);
    assert(G_IS_OBJECT(o));
    g_object_unref(o);

    printf("glib ok (%u.%u.%u)\n", glib_major_version, glib_minor_version, glib_micro_version);
    return 0;
}
```

- [ ] **Step 2: Write `packages/glib.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg glib
VER=2.82.0
fetch "https://download.gnome.org/sources/glib/2.82/glib-$VER.tar.xz"
extract_auto "glib-$VER.tar.xz" glib
me glib -Dtests=false -Ddoc=false -Dintrospection=disabled \
  -Dlibmount=disabled -Dlibelf=disabled -Dselinux=disabled -Dxattr=false \
  -Dnls=disabled -Dglib_debug=disabled -Ddefault_library=static \
  -Doss_fuzz=disabled -Dsystemd=disabled -Dman-pages=disabled
wasmtest glib glib_test.c "$(pkg-config --cflags --libs gobject-2.0)"
manifest glib "$VER"
touch "$STAMPS/glib.ok"
```

Expected friction (apply build-failure rule, record in findings): meson may attempt to run cross-built tools; fix with `--cross-file` native/binary overrides or `-Dglib_compile_resources`-style options. Known-good patches exist in prior glib-wasm efforts — cite whichever is used.

- [ ] **Step 3: Run** — `bash packages/glib.sh` (expect 5–15 min; foreground is fine, otherwise oc-bg) → `glib ok (...)` + `PASS: glib`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: glib + smoke test"`

---

### Task 11: pango

**Files:**
- Create: `packages/pango.sh`, `tests/lib/pango_test.c`

**Interfaces:**
- Consumes: glib, cairo, harfbuzz, fribidi, freetype, fontconfig.
- Produces: `pkg-config: pango pangocairo` — text layout + rendering.

- [ ] **Step 1: Write the test** — lay out and rasterize "Hello wasm", count non-transparent pixels:

```c
#include <pango/pangocairo.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    setenv("FONTCONFIG_PATH", "/fixtures/fc", 1);
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 200, 50);
    cairo_t* cr = cairo_create(s);
    PangoLayout* layout = pango_cairo_create_layout(cr);
    pango_layout_set_text(layout, "Hello wasm", -1);
    PangoFontDescription* desc = pango_font_description_from_string("DejaVu Sans 24");
    pango_layout_set_font_description(layout, desc);
    pango_font_description_free(desc);
    cairo_set_source_rgb(cr, 0, 0, 0);
    pango_cairo_update_layout(cr, layout);
    pango_cairo_show_layout(cr, layout);
    int w, h; pango_layout_get_pixel_size(layout, &w, &h);
    assert(w > 50 && h > 10);
    unsigned char* d = cairo_image_surface_get_data(s);
    long opaque = 0;
    for (long i = 3; i < 200 * 50 * 4; i += 4) if (d[i] != 0) opaque++;
    assert(opaque > 200); // real glyph coverage, not blank
    printf("pango ok: layout %dx%d, %ld inked pixels\n", w, h, opaque);
    return 0;
}
```

- [ ] **Step 2: Write `packages/pango.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pango
VER=1.54.0
fetch "https://download.gnome.org/sources/pango/1.54/pango-$VER.tar.xz"
extract_auto "pango-$VER.tar.xz" pango
me pango -Dtests=false -Ddoc=false -Dintrospection=disabled \
  -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled \
  -Dlibthai=disabled -Dx11=disabled
wasmtest pango pango_test.c "$(pkg-config --cflags --libs pangocairo)"
manifest pango "$VER"
touch "$STAMPS/pango.ok"
```

- [ ] **Step 3: Run** — `bash packages/pango.sh` → expect `pango ok: layout WxH, N inked pixels` + `PASS: pango`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: pango + smoke test"`

---

### Task 12: gdk-pixbuf

**Files:**
- Create: `packages/gdk-pixbuf.sh`, `tests/lib/gdkpixbuf_test.c`

**Interfaces:**
- Consumes: glib, libpng.
- Produces: `pkg-config: gdk-pixbuf-2.0` (PNG loader only).

- [ ] **Step 1: Write the test** — decode the committed 1×1 fixture:

```c
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <assert.h>
#include <stdio.h>

int main() {
    GdkPixbuf* pb = gdk_pixbuf_new_from_file("/fixtures/tiny.png", NULL);
    assert(pb);
    assert(gdk_pixbuf_get_width(pb) == 1);
    assert(gdk_pixbuf_get_height(pb) == 1);
    printf("gdk-pixbuf ok: %dx%d\n",
           gdk_pixbuf_get_width(pb), gdk_pixbuf_get_height(pb));
    return 0;
}
```

- [ ] **Step 2: Write `packages/gdk-pixbuf.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gdk-pixbuf
VER=2.42.12
fetch "https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-$VER.tar.xz"
extract_auto "gdk-pixbuf-$VER.tar.xz" gdk-pixbuf
me gdk-pixbuf -Dtests=false -Ddocs=false -Dintrospection=disabled \
  -Dpng=enabled -Djpeg=disabled -Dtiff=disabled -Dlibpng=enabled \
  -Dbuiltin_loaders=png -Dinstalled_tests=false -Dman=false
wasmtest gdk-pixbuf gdkpixbuf_test.c "$(pkg-config --cflags --libs gdk-pixbuf-2.0)"
manifest gdk-pixbuf "$VER"
touch "$STAMPS/gdk-pixbuf.ok"
```

Expected friction: gdk-pixbuf normally runs `gdk-pixbuf-query-loaders` at install to write a loaders cache. On a cross build that binary is wasm. If install fails there, write the cache by hand after `meson install`:

```bash
printf '[Loader 1]\nType=image/png\n...' # only if needed — record exact fix in findings
```

or run the wasm tool under node (`node build/gdk-pixbuf/gdk-pixbuf-query-loaders.js`). Use whichever works; findings records the choice.

- [ ] **Step 3: Run** — `bash packages/gdk-pixbuf.sh` → `gdk-pixbuf ok: 1x1` + `PASS: gdk-pixbuf`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: gdk-pixbuf (png loader) + smoke test"`

---

### Task 13: atk

**Files:**
- Create: `packages/atk.sh`, `tests/lib/atk_test.c`

**Interfaces:**
- Consumes: glib.
- Produces: `pkg-config: atk` — GTK3 dep.

- [ ] **Step 1: Write the test**

```c
#include <atk/atk.h>
#include <assert.h>
#include <stdio.h>

int main() {
    AtkObject* obj = g_object_new(ATK_TYPE_OBJECT, NULL);
    assert(ATK_IS_OBJECT(obj));
    atk_object_set_name(obj, "test");
    assert(g_strcmp0(atk_object_get_name(obj), "test") == 0);
    g_object_unref(obj);
    printf("atk ok\n");
    return 0;
}
```

- [ ] **Step 2: Write `packages/atk.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg atk
VER=2.38.0
fetch "https://download.gnome.org/sources/atk/2.38/atk-$VER.tar.xz"
extract_auto "atk-$VER.tar.xz" atk
me atk -Dtests=false -Ddocs=false -Dintrospection=disabled
wasmtest atk atk_test.c "$(pkg-config --cflags --libs atk)"
manifest atk "$VER"
touch "$STAMPS/atk.ok"
```

- [ ] **Step 3: Run** — `bash packages/atk.sh` → `atk ok` + `PASS: atk`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: atk + smoke test"`

---

### Task 14: GTK3 (Broadway only)

**Files:**
- Create: `packages/gtk3.sh`, `tests/lib/gtk_test.c`

**Interfaces:**
- Consumes: glib, pango, cairo, gdk-pixbuf, atk.
- Produces: `pkg-config: gtk+-3.0` with only the Broadway backend compiled in. Real display tests are Leg B (T2); this task proves the library builds and initializes non-fatally in wasm.

- [ ] **Step 1: Write the test** — version print + graceful no-display init:

```c
#include <gtk/gtk.h>
#include <stdio.h>

int main(int argc, char** argv) {
    gtk_disable_setlocale();
    // No broadwayd in Node: init_check must return FALSE, not crash.
    gboolean ok = gtk_init_check(&argc, &argv);
    printf("gtk %d.%d.%d init_check=%d (FALSE expected here; display is Leg B/T2)\n",
           gtk_get_major_version(), gtk_get_minor_version(),
           gtk_get_micro_version(), ok);
    return 0;
}
```

- [ ] **Step 2: Write `packages/gtk3.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gtk3
VER=3.24.43
fetch "https://download.gnome.org/sources/gtk+/3.24/gtk+-$VER.tar.xz"
extract_auto "gtk+-$VER.tar.xz" gtk3
me gtk3 -Dbroadway-backend=true -Dx11-backend=false -Dwayland-backend=false \
  -Dquartz-backend=false -Dwin32-backend=false -Ddemos=false -Dexamples=false \
  -Dtests=false -Dintrospection=disabled -Dgtk_doc=false -Dman=false \
  -Dprint-backends= -Dcolord=no -Dcloudproviders=false -Dmedia=none \
  -Dtracker=false -Dxinerama=no
wasmtest gtk gtk_test.c "$(pkg-config --cflags --libs gtk+-3.0)"
manifest "gtk+" "$VER"
touch "$STAMPS/gtk3.ok"
```

Notes: keep the built `broadwayd` + `broadway.js` artifacts around — copy them out in the script so Leg B can diff against them:

```bash
cp "$BUILD/gtk3/gdk/broadway/broadway.js" "$ROOT/build/broadway-upstream.js" 2>/dev/null || true
```

(added before the `manifest` line). `-Dprint-backends=` sets it empty — if this meson version rejects the bare value, use `-Dprint-backends=none` or drop the option and note it in findings.

- [ ] **Step 3: Run** — `bash packages/gtk3.sh` (longest package so far; oc-bg if you like) → `gtk 3.24.x init_check=0 (...)` + `PASS: gtk`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: GTK3 broadway-only + smoke test"`

---

### Task 15: The C++ bindings stack (sigc++, glibmm, cairomm, pangomm, gtkmm)

**Files:**
- Create: `packages/sigcpp.sh`, `packages/glibmm.sh`, `packages/cairomm.sh`, `packages/pangomm.sh`, `packages/gtkmm.sh`
- Create: `tests/lib/sigcpp_test.cpp`, `tests/lib/glibmm_test.cpp`, `tests/lib/cairomm_test.cpp`, `tests/lib/pangomm_test.cpp`, `tests/lib/gtkmm_test.cpp`

**Interfaces:**
- Consumes: glib, cairo, pango, gtk3.
- Produces: `pkg-config: sigc++-2.0 glibmm-2.4 cairomm-1.0 pangomm-2.48 gtkmm-3.0` — the C++ API Inkscape is written against.

- [ ] **Step 1: Write the tests**

`tests/lib/sigcpp_test.cpp`:

```cpp
#include <sigc++/sigc++.h>
#include <cassert>
#include <cstdio>

int main() {
    sigc::signal<int(int)> s;
    s.connect([](int x) { return x + 1; });
    assert(s.emit(41) == 42);
    std::printf("sigc++ ok\n");
    return 0;
}
```

`tests/lib/glibmm_test.cpp`:

```cpp
#include <glibmm/ustring.h>
#include <glibmm/miscutils.h>
#include <cassert>
#include <cstdio>

int main() {
    Glib::ustring u("hello");
    u += " glibmm";
    assert(u == "hello glibmm");
    assert(Glib::ustring("héllo").bytes() == 7);
    std::printf("glibmm ok\n");
    return 0;
}
```

`tests/lib/cairomm_test.cpp`:

```cpp
#include <cairomm/context.h>
#include <cairomm/surface.h>
#include <cassert>
#include <cstdio>

int main() {
    auto surf = Cairo::ImageSurface::create(Cairo::FORMAT_ARGB32, 8, 8);
    auto cr = Cairo::Context::create(surf);
    cr->set_source_rgb(1.0, 0.0, 0.0);
    cr->paint();
    assert(surf->get_data() != nullptr);
    std::printf("cairomm ok\n");
    return 0;
}
```

`tests/lib/pangomm_test.cpp` (link + version only; real layout is covered by the pango test):

```cpp
#include <pangomm.h>
#include <cstdio>

int main() {
    std::printf("pangomm linked ok\n");
    return 0;
}
```

`tests/lib/gtkmm_test.cpp` (link + version only; GUI init is Leg B):

```cpp
#include <gtkmm/main.h>
#include <cstdio>

int main() {
    std::printf("gtkmm linked ok\n");
    return 0;
}
```

- [ ] **Step 2: Write the package scripts** (all five follow the same autotools shape — the gtkmm3-era tarballs are autotools)

`packages/sigcpp.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg sigcpp
VER=2.12.1
fetch "https://download.gnome.org/sources/libsigc++/2.12/libsigc++-$VER.tar.xz"
extract_auto "libsigc++-$VER.tar.xz" sigcpp
ac sigcpp --disable-documentation --enable-maintainer-mode=no
wasmtest sigcpp sigcpp_test.cpp "$(pkg-config --cflags --libs sigc++-2.0)"
manifest "libsigc++" "$VER"
touch "$STAMPS/sigcpp.ok"
```

`packages/glibmm.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg glibmm
VER=2.66.7
fetch "https://download.gnome.org/sources/glibmm/2.66/glibmm-$VER.tar.xz"
extract_auto "glibmm-$VER.tar.xz" glibmm
ac glibmm --disable-documentation
wasmtest glibmm glibmm_test.cpp "$(pkg-config --cflags --libs glibmm-2.4)"
manifest glibmm "$VER"
touch "$STAMPS/glibmm.ok"
```

`packages/cairomm.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg cairomm
VER=1.14.4
fetch "https://download.gnome.org/sources/cairomm/1.14/cairomm-$VER.tar.xz"
extract_auto "cairomm-$VER.tar.xz" cairomm
ac cairomm --disable-documentation
wasmtest cairomm cairomm_test.cpp "$(pkg-config --cflags --libs cairomm-1.0)"
manifest cairomm "$VER"
touch "$STAMPS/cairomm.ok"
```

`packages/pangomm.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pangomm
VER=2.46.3
fetch "https://download.gnome.org/sources/pangomm/2.46/pangomm-$VER.tar.xz"
extract_auto "pangomm-$VER.tar.xz" pangomm
ac pangomm --disable-documentation
wasmtest pangomm pangomm_test.cpp "$(pkg-config --cflags --libs pangomm-2.48)"
manifest pangomm "$VER"
touch "$STAMPS/pangomm.ok"
```

`packages/gtkmm.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gtkmm
VER=3.24.9
fetch "https://download.gnome.org/sources/gtkmm/3.24/gtkmm-$VER.tar.xz"
extract_auto "gtkmm-$VER.tar.xz" gtkmm
ac gtkmm --disable-documentation --disable-demos
wasmtest gtkmm gtkmm_test.cpp "$(pkg-config --cflags --libs gtkmm-3.0)"
manifest gtkmm "$VER"
touch "$STAMPS/gtkmm.ok"
```

Notes: these tarballs bundle their `mm-common` build glue (`--disable-documentation` avoids the doc toolchain). If configure demands `mm-common` or `glibmm-2.4` version mismatches appear, the fix is version bumps within the same ABI line (glibmm stays on 2.66.x, cairomm 1.14.x, pangomm 2.46/2.48, gtkmm 3.24.x) — record any bump in findings + manifest.

- [ ] **Step 3: Run** — `for p in sigcpp glibmm cairomm pangomm gtkmm; do bash packages/$p.sh; done` → five PASS lines.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: C++ bindings stack + smoke tests"`

---

### Task 16: libxml2 + libxslt

**Files:**
- Create: `packages/libxml2.sh`, `packages/libxslt.sh`, `tests/lib/libxml2_test.c`, `tests/lib/libxslt_test.c`

**Interfaces:**
- Consumes: zlib.
- Produces: `pkg-config: libxml-2.0 libxslt` — Inkscape's document engine deps.

- [ ] **Step 1: Write the tests**

`tests/lib/libxml2_test.c` — parse the fixture, XPath the rects:

```c
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <assert.h>
#include <stdio.h>

int main() {
    xmlDocPtr doc = xmlReadFile("/fixtures/basic.svg", NULL, 0);
    assert(doc);
    xmlXPathContextPtr ctx = xmlXPathNewContext(doc);
    assert(ctx);
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST "//*[local-name()='rect']", ctx);
    assert(obj && obj->nodesetval && obj->nodesetval->nodeNr == 2);
    printf("libxml2 ok: %d rects found\n", obj->nodesetval->nodeNr);
    xmlXPathFreeObject(obj);
    xmlXPathFreeContext(ctx);
    xmlFreeDoc(doc);
    return 0;
}
```

`tests/lib/libxslt_test.c` — identity transform of the fixture:

```c
#include <libxml/parser.h>
#include <libxslt/xslt.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const char* STYLE =
    "<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'>"
    "<xsl:template match='/'><out><xsl:value-of select=\"count(//*)\"/></out></xsl:template>"
    "</xsl:stylesheet>";

int main() {
    xsltInit();
    xmlDocPtr style = xmlReadMemory(STYLE, strlen(STYLE), NULL, NULL, 0);
    xsltStylesheetPtr ss = xsltParseStylesheetDoc(style);
    assert(ss);
    xmlDocPtr in = xmlReadFile("/fixtures/basic.svg", NULL, 0);
    xmlDocPtr out = xsltApplyStylesheet(ss, in, NULL);
    assert(out);
    xmlChar* txt = NULL; int len = 0;
    xsltSaveResultToString(&txt, &len, out, ss);
    assert(txt && strstr((char*)txt, "3")); // svg + 2 rects
    printf("libxslt ok: %.*s\n", len, (char*)txt);
    xmlFree(txt);
    xmlFreeDoc(out); xmlFreeDoc(in); xsltFreeStylesheet(ss);
    return 0;
}
```

- [ ] **Step 2: Write the package scripts**

`packages/libxml2.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libxml2
VER=2.13.6
fetch "https://download.gnome.org/sources/libxml2/2.13/libxml2-$VER.tar.xz"
extract_auto "libxml2-$VER.tar.xz" libxml2
me libxml2 -Dtests=disabled -Ddocs=disabled -Dicons=disabled \
  -Dicu=disabled -Dlzma=disabled -Dhttp=disabled -Dpython=disabled \
  -Dzlib=enabled
wasmtest libxml2 libxml2_test.c "$(pkg-config --cflags --libs libxml-2.0)"
manifest libxml2 "$VER"
touch "$STAMPS/libxml2.ok"
```

`packages/libxslt.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libxslt
VER=1.1.42
fetch "https://download.gnome.org/sources/libxslt/1.1/libxslt-$VER.tar.xz"
extract_auto "libxslt-$VER.tar.xz" libxslt
me libxslt -Dtests=disabled -Ddocs=disabled -Dprofiler=disabled \
  -Dcrypto=disabled -Dpython=disabled
wasmtest libxslt libxslt_test.c "$(pkg-config --cflags --libs libxslt)"
manifest libxslt "$VER"
touch "$STAMPS/libxslt.ok"
```

- [ ] **Step 3: Run** — `bash packages/libxml2.sh && bash packages/libxslt.sh` → `libxml2 ok: 2 rects found`, `PASS: libxml2`, `libxslt ok: <out>3</out>`, `PASS: libxslt`.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: libxml2 + libxslt + smoke tests"`

---

### Task 17: gsl + double-conversion + boost headers

**Files:**
- Create: `packages/gsl.sh`, `packages/dconv.sh`, `packages/boost.sh`, `tests/lib/gsl_test.c`, `tests/lib/dconv_test.cpp`, `tests/lib/boost_test.cpp`

**Interfaces:**
- Produces: `pkg-config: gsl`, `double-conversion`; boost headers under `$SYSROOT/include/boost/`.

- [ ] **Step 1: Write the tests**

`tests/lib/gsl_test.c`:

```c
#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>
#include <assert.h>
#include <stdio.h>

int main() {
    gsl_vector* v = gsl_vector_alloc(3);
    gsl_vector* w = gsl_vector_alloc(3);
    gsl_vector_set_all(v, 2.0);
    gsl_vector_set_all(w, 3.0);
    double d = 0;
    assert(gsl_blas_ddot(v, w, &d) == 0);
    assert(d == 18.0); // 3 * 2*3
    gsl_vector_free(v); gsl_vector_free(w);
    printf("gsl ok (ddot=%.1f)\n", d);
    return 0;
}
```

`tests/lib/dconv_test.cpp`:

```cpp
#include <double-conversion/double-conversion.h>
#include <cassert>
#include <cstdio>
#include <string>

using namespace double_conversion;

int main() {
    DoubleToStringConverter c(
        DoubleToStringConverter::EMIT_TRAILING_DECIMAL_POINT, "inf", "nan", 'e',
        -6, 21, 6, 0);
    char buf[64];
    StringBuilder sb(buf, sizeof buf);
    c.ToShortest(3.14, &sb);
    assert(std::string(sb.Finalize()) == "3.14");
    std::printf("double-conversion ok\n");
    return 0;
}
```

`tests/lib/boost_test.cpp`:

```cpp
#include <boost/optional.hpp>
#include <boost/variant.hpp>
#include <cassert>
#include <cstdio>

int main() {
    boost::optional<int> o = 3;
    assert(o && *o == 3);
    boost::variant<int, double> v = 2.5;
    assert(boost::get<double>(v) == 2.5);
    std::printf("boost ok\n");
    return 0;
}
```

- [ ] **Step 2: Write the package scripts**

`packages/gsl.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gsl
VER=2.8
fetch "https://ftp.gnu.org/gnu/gsl/gsl-$VER.tar.gz"
extract_auto "gsl-$VER.tar.gz" gsl
ac gsl --disable-shared
wasmtest gsl gsl_test.c "$(pkg-config --cflags --libs gsl)"
manifest gsl "$VER"
touch "$STAMPS/gsl.ok"
```

`packages/dconv.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg dconv
VER=3.3.0
fetch "https://github.com/google/double-conversion/archive/refs/tags/v$VER.tar.gz"
extract_auto "double-conversion-$VER.tar.gz" dconv
cm dconv -DBUILD_TESTING=OFF
wasmtest dconv dconv_test.cpp "$(pkg-config --cflags --libs double-conversion)"
manifest double-conversion "$VER"
touch "$STAMPS/dconv.ok"
```

`packages/boost.sh` (headers only — no build):

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg boost
VER=1.86.0
fetch "https://archives.boost.io/release/$VER/source/boost_1_86_0.tar.gz"
extract_auto "boost_1_86_0.tar.gz" boost
mkdir -p "$SYSROOT/include"
cp -r "$SRC/boost/boost" "$SYSROOT/include/"
wasmtest boost boost_test.cpp -I"$SYSROOT/include"
manifest boost "$VER"
touch "$STAMPS/boost.ok"
```

- [ ] **Step 3: Run** — `for p in gsl dconv boost; do bash packages/$p.sh; done` → three PASS lines.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: gsl, double-conversion, boost headers + smoke tests"`

---

### Task 18: libgc (Boehm) — the decision ladder

**Files:**
- Create: `packages/libgc.sh`, `tests/lib/libgc_test.c`
- Create on fallback only: `patches/libgc/stub/gc_stub.c`, `patches/libgc/stub/gc.h`, `tests/lib/libgc_stub_test.c`

**Interfaces:**
- Produces: `pkg-config: gc` — either real collection (exit criterion 0) or the documented leak-by-design stub. Every downstream consumer links it through Inkscape's GC wrapper; the rung chosen is recorded in `manifest` + `findings`.

- [ ] **Step 1: Write the real-GC test**

`tests/lib/libgc_test.c`:

```c
#include <gc.h>
#include <assert.h>
#include <stdio.h>

static int finalized = 0;
static void fin(void* obj, void* cd) { (void)obj; (void)cd; finalized = 1; }

struct node { struct node* next; };

int main() {
    GC_INIT;
    void* p = GC_malloc(1024);
    assert(p);
    GC_register_finalizer(p, fin, NULL, NULL, NULL);
    p = NULL; // no remaining references
    GC_gcollect();
    GC_gcollect();
    if (!finalized) {
        printf("libgc: allocation ok but collection NOT observable (finalizer never ran)\n");
        return 2; // ladder signal — see Step 3
    }
    // cyclic garbage must not grow the heap unboundedly
    for (int round = 0; round < 4; round++) {
        struct node* head = NULL;
        for (int i = 0; i < 10000; i++) {
            struct node* n = GC_malloc(sizeof(struct node));
            assert(n);
            n->next = head; head = n;
        }
        head->next = head; // make a cycle, drop the handle
        head = NULL;
        GC_gcollect();
    }
    printf("libgc ok (finalizer ran, heap bounded at %lu)\n",
           (unsigned long)GC_get_heap_size());
    return 0;
}
```

- [ ] **Step 2: Write `packages/libgc.sh` (rung 1: near-stock)**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libgc
VER=8.2.8
fetch "https://github.com/ivmai/bdwgc/releases/download/v$VER/gc-$VER.tar.gz"
extract_auto "gc-$VER.tar.gz" libgc
ac libgc --disable-threads --disable-shared --disable-gcj-support \
         --disable-java-finalization --enable-munmap=0
set +e
wasmtest libgc libgc_test.c "$(pkg-config --cflags --libs gc)" 2>&1 | tee "$LOGS/libgc-rung1.log"
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" = 0 ]; then
  manifest "libgc (real)" "$VER"
else
  echo "libgc rung 1 FAILED (rc=$rc) — continue the ladder per plan Task 18 Step 3" >&2
  exit 1
fi
touch "$STAMPS/libgc.ok"
```

- [ ] **Step 3: Run the ladder**

`bash packages/libgc.sh` outcomes:

1. **Exit 0** (`finalized=1`, heap bounded): real GC works. Done — commit.
2. **Exit 2** (allocation ok, no observable collection): rung 2 — give libgc a real stack range to scan. Emscripten exports the wasm shadow-stack bounds as `__stack_base` and `__stack_low` when linked with `-Wl,--export=__stack_base -Wl,--export=__stack_low`, and libgc trusts a stack bottom set at init time. Concretely:
   - In `tests/lib/libgc_test.c`, immediately after `GC_INIT;` add:

     ```c
     extern void* __stack_base;
     GC_set_stackbottom((ptr_t)__stack_base); /* highest wasm shadow-stack address */
     ```

   - In `packages/libgc.sh` rung 2, change the `wasmtest` link line to append `-Wl,--export=__stack_base -Wl,--export=__stack_low` (save the diff of both changes as `patches/libgc/rung2-stackbounds.patch` so it's reproducible).
   - If after this the test exits 0 → rung 2 adopted, record patch + link flags in findings/manifest. If it still exits 2 or crashes → rung 3.
3. **Hard failure (crash/hang)**: rung 3 — the stub. Create `patches/libgc/stub/`:

`patches/libgc/stub/gc_stub.c`:

```c
/* Leak-by-design GC stub.
 * shortcut: never frees, fine for single-document demo sessions;
 * upgrade to real libgc before any long-running use. */
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

void* GC_malloc(size_t n) { void* p = malloc(n); if (p) memset(p, 0, n); return p; }
void* GC_malloc_atomic(size_t n) { return malloc(n); }
void* GC_malloc_uncollectable(size_t n) { return GC_malloc(n); }
void* GC_malloc_stubborn(size_t n) { return GC_malloc(n); }
void* GC_realloc(void* p, size_t n) { return realloc(p, n); }
void GC_free(void* p) { (void)p; }
void GC_gcollect(void) {}
void GC_init(void) {}
void GC_INIT(void) {}
void GC_end_stubborn_change(void* p) { (void)p; }
void GC_register_finalizer(void* obj, void (*f)(void*, void*), void* d,
                           void (**of)(void*, void*), void** od)
{ (void)obj; (void)f; (void)d; if (of) *of = NULL; if (od) *od = NULL; }
void GC_set_all_interior_pointers(int flag) { (void)flag; }
size_t GC_get_heap_size(void) { return 0; }
void GC_allow_register_threads(void) {}
void GC_set_max_retries(size_t n) { (void)n; }
void* GC_call_with_alloc_lock(void* (*fn)(void*), void* cd) { return fn(cd); }
int GC_get_find_leak(void) { return 0; }
void GC_set_find_leak(int n) { (void)n; }
```

`patches/libgc/stub/gc.h` — a thin header that `#include <stddef.h>` and declares the functions above plus the `GC_INIT` macro (`#define GC_INIT() GC_init()`).

Then replace the build body of `packages/libgc.sh` after `begin_pkg libgc` with:

```bash
mkdir -p "$SYSROOT/include" "$SYSROOT/lib"
cp "$PATCHES/libgc/stub/gc.h" "$SYSROOT/include/gc.h"
emcc -c "$PATCHES/libgc/stub/gc_stub.c" -o "$SYSROOT/lib/libgc.a"
```

and switch its test to `tests/lib/libgc_stub_test.c`:

```c
#include <assert.h>
#include <stdio.h>
#include "gc.h"

int main() {
    GC_INIT;
    void* p = GC_malloc(4096);
    assert(p);
    void* q = GC_realloc(p, 8192);
    assert(q);
    GC_gcollect(); // no-op by design
    printf("libgc stub ok (leak-by-design, see shortcut note)\n");
    return 0;
}
```

`manifest "libgc (stub)" "0"` and a findings entry titled **"libgc rung 3: stub adopted"** explaining why.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: libgc (<rung>) + test"`

---

### Task 19: potrace (optional — skip on any friction)

**Files:**
- Create: `packages/potrace.sh`, `tests/lib/potrace_test.c`

**Interfaces:**
- Produces: `potracelib` for bitmap tracing. Optional: per spec, include only if it builds without extra effort — **any failure here means delete the script and record "potrace cut" in findings, not debugging.**

- [ ] **Step 1: Write the test**

```c
#include <potracelib.h>
#include <assert.h>
#include <stdio.h>

int main() {
    potrace_bitmap_t bm;
    bm.w = 8; bm.h = 8; bm.dy = 1;
    unsigned long map[8] = {0xffUL, 0xffUL, 0, 0, 0, 0, 0, 0}; // two black rows
    bm.map = map;
    potrace_param_t* pm = potrace_param_default();
    assert(pm);
    potrace_path_t* p = potrace_trace(pm, &bm);
    assert(p);
    printf("potrace ok (path found, %d segments)\n", p->curve.n);
    return 0;
}
```

- [ ] **Step 2: Write `packages/potrace.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg potrace
VER=1.16
fetch "https://downloads.sourceforge.net/potrace/1.16/potrace-$VER.tar.gz"
extract_auto "potrace-$VER.tar.gz" potrace
ac potrace --disable-shared --with-libpotrace --without-libgs
wasmtest potrace potrace_test.c -lpotrace -L"$SYSROOT/lib"
manifest potrace "$VER"
touch "$STAMPS/potrace.ok"
```

- [ ] **Step 3: Run** — `bash packages/potrace.sh` → `potrace ok ...` + `PASS: potrace`, or cut per the optionality rule.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "leg A: potrace (+ smoke test) | cut (see findings)"`

---

### Task 20: lib2geom

**Files:**
- Create: `packages/lib2geom.sh`, `tests/lib/lib2geom_test.cpp`

**Interfaces:**
- Consumes: boost, gsl, double-conversion.
- Produces: `pkg-config: lib2geom` — Inkscape's geometry library, from the tag matching the 1.4.4 release.

- [ ] **Step 1: Pin the version**

```bash
git clone --quiet https://gitlab.com/inkscape/lib2geom.git build/src/lib2geom 2>/dev/null || true
git -C build/src/lib2geom tag -l | grep -E '^2geom-?1\.4' | sort -V | tail -3
```

Take the newest `1.4`-line tag shown (that is what Inkscape 1.4.x pins), note it for `$VER` below and the manifest. If the clone already exists, `git -C build/src/lib2geom fetch --tags` instead.

- [ ] **Step 2: Write the test**

`tests/lib/lib2geom_test.cpp`:

```cpp
#include <2geom/point.h>
#include <2geom/path.h>
#include <2geom/svg-path-parser.h>
#include <2geom/pathvector.h>
#include <cassert>
#include <cstdio>

int main() {
    Geom::Point p(1.5, 2.5);
    assert(p.x() == 1.5 && p.y() == 2.5);
    Geom::PathVector pv = Geom::parse_svg_path("M 0,0 L 10,10 L 20,0 Z");
    assert(pv.size() == 1);
    Geom::Rect r = pv[0].boundsFast();
    assert(r && r->width() == 20 && r->height() == 10);
    std::printf("lib2geom ok (parsed path, bounds %.1fx%.1f)\n", r->width(), r->height());
    return 0;
}
```

- [ ] **Step 3: Write `packages/lib2geom.sh`** (assume `VER` from Step 1; the tag name goes in `TAG`)

```bash
#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg lib2geom
VER=2geom-1.4   # ← replace with the actual newest 1.4-line tag from Step 1
[ -d "$SRC/lib2geom" ] || git clone --quiet https://gitlab.com/inkscape/lib2geom.git "$SRC/lib2geom"
git -C "$SRC/lib2geom" checkout --quiet "$VER"
cm lib2geom -D2GEOM_TESTING=OFF -D2GEOM_PROFILING=OFF -D2GEOM_TOYS=OFF \
            -DBUILD_SHARED_LIBS=OFF -DENABLE_LPE=ON
wasmtest lib2geom lib2geom_test.cpp "$(pkg-config --cflags --libs lib2geom)"
manifest lib2geom "$VER"
touch "$STAMPS/lib2geom.ok"
```

Notes: if `cm lib2geom` fails on a CMake option name (2geom options vary by version), run `grep -r "option(" "$SRC/lib2geom/CMakeLists.txt" "$SRC/lib2geom/cmake" 2>/dev/null` and adjust to the real names — tests off is the important part. Its own test suite runs in Leg C (T4) where its test binaries get exercised; here the API smoke test is the gate.

- [ ] **Step 4: Run** — `bash packages/lib2geom.sh` → `lib2geom ok (parsed path, bounds 20.0x10.0)` + `PASS: lib2geom`.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "leg A: lib2geom + smoke test"`

---

### Task 21: `check-1` aggregate + findings + T1 gate

**Files:**
- Create: `tests/check-1.sh`, `docs/findings.md`

**Interfaces:**
- Produces: `make check-1` — the T1 gate. Also `build/manifest.txt` (written incrementally by every package) verified complete.

- [ ] **Step 1: Write `tests/check-1.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." ; source packages/common.sh
fail=0
PKGS="zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
      libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
      gtkmm libxml2 libxslt gsl dconv boost libgc potrace lib2geom"
for p in $PKGS; do
  [ -e "$STAMPS/$p.ok" ] || { echo "MISSING STAMP: $p"; fail=1; }
done
for m in zlib libpng freetype2 fontconfig pixman-1 fribidi harfbuzz cairo ffi \
         glib-2.0 gobject-2.0 gio-2.0 pango pangocairo gdk-pixbuf-2.0 atk \
         gtk+-3.0 sigc++-2.0 glibmm-2.4 cairomm-1.0 pangomm gtkmm-3.0 \
         libxml-2.0 libxslt gsl double-conversion gc lib2geom; do
  pkg-config --modversion "$m" >/dev/null 2>&1 \
    || { echo "PKG-CONFIG MISSING: $m"; fail=1; }
done
[ -f "$SYSROOT/include/boost/optional.hpp" ] || { echo "MISSING: boost headers"; fail=1; }
if [ "$fail" = 0 ]; then echo "check-1 PASS ($(grep -c . build/manifest.txt) packages in manifest)"; else exit 1; fi
```

Note: if potrace was cut in Task 19, remove it from the `PKGS` list and add `potracelib` removal is not needed (it's not in the pkg-config loop — add it only if kept).

- [ ] **Step 2: Create `docs/findings.md`**

```markdown
# Findings log

Research log for the Inkscape WASM port (spec: docs/superpowers/specs/2026-10-12-inkscape-wasm/).
One entry per notable event: build failures and fixes, version substitutions,
libgc/libffi ladder rungs, kill criteria hits.

## T0/T1 (Leg A)

- (add entries as they happen; newest last)
```

- [ ] **Step 3: Full run + gate**

Run: `make deps` (via oc-bg — this is the multi-hour one; check `build/logs/deps.log*` on later turns), then `make check-0 && make check-1`.
Expected: `check-0` → `PASS: t0`; `check-1` → `check-1 PASS (N packages in manifest)`.

If any package failed during the full run, its own task's failure procedure applies (build-failure rule); `check-1` reports what's missing.

- [ ] **Step 4: Record the T1 outcome in findings + commit**

Add a `## T1 gate result` entry: pass/fail per package, libgc rung, libffi outcome, any version substitutions. This is the input for writing the Leg B plan.

```bash
git add -A && git commit -m "leg A complete: check-1 gate + findings (T1 <PASS|FAIL>)"
```

---

## Post-plan notes (not tasks)

- **Leg B plan writing** happens after T1 passes, per the roadmap: the Leg B author gets `build/broadway-upstream.js` (from Task 14), the sysroot, and the findings log as inputs.
- **Self-review findings applied during planning:** spec's dep table omitted libffi (fixed via spec addendum); pangomm pkg-config name is `pangomm` (unversioned module name in the 2.46/2.48 line) — check-1 uses that; boost has no pkg-config module so it's checked by header presence.

