#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gtk3
VER=3.24.43
fetch "https://download.gnome.org/sources/gtk+/3.24/gtk+-$VER.tar.xz"
rm -rf "$SRC/gtk3" "$BUILD/gtk3" # overlapping patches break each other's reverse guards; always fresh
extract_auto "gtk+-$VER.tar.xz" gtk3
grep -q "to-pixdata" "$SRC/gtk3/gtk/gen-gtk-gresources-xml.py" \
  && patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-to-pixdata.patch"
grep -q "!= 'emscripten'" "$SRC/gtk3/gtk/meson.build" \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-tool-install-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/no-print-backend-module.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-print-backend-module.patch"
# wasm strict function types: 162 1-arg iface_init fns registered as 2-arg
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/iface-init-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/iface-init-signatures.patch"
# wasm: direct callers of the now-2-arg delegate iface_init
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "patches/gtk3/filechooser-delegate-calls.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "patches/gtk3/filechooser-delegate-calls.patch"
# wasm: broadway over the in-module bridge (leg B) — app seam, daemon glue
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadway-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadway-bridge-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadwayd-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadwayd-bridge-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadway-server-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadway-server-bridge-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/clean-boot-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/clean-boot-emscripten.patch"
# Libraries only: gtk's own executables (broadwayd aside) can't link on
# emscripten (meson injects -pthread into exe links). broadwayd itself is
# reused as source in leg B, not linked here.
# bridge headers into the sysroot — gdk + daemon sources #include <bridge.h>
mkdir -p "$SYSROOT/include" && cp "$ROOT"/bridge/*.h "$SYSROOT/include/"
meson setup "$BUILD/gtk3" "$SRC/gtk3" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbroadway_backend=true -Dx11_backend=false -Dwayland_backend=false \
  -Dwin32_backend=false -Dquartz_backend=false \
  -Dgtk_doc=false -Dman=false -Dintrospection=false \
  -Dtests=false -Ddemos=false -Dexamples=false -Dinstalled_tests=false \
  -Dbuiltin_immodules=all \
  -Dcolord=no -Dprint_backends=file -Dcloudproviders=false -Dtracker3=false
# Libraries + broadwayd only (leg-B donor); the other gtk tools are not
# installed (see no-tool-install patch) and can't link on emscripten.
# Libraries only (tools hit wasm-opt fpcast-emu's param limit at link:
# "max-func-params needs to be at least 17"); broadwayd is the leg-B donor —
# try to link it and preserve its artifacts, but tolerate failure.
ninja -C "$BUILD/gtk3" -j 64 gdk/libgdk-3.a gtk/libgtk-3.a libgail-util/libgailutil-3.a \
  gdk/broadway/broadwayd.js \
  $(ninja -C "$BUILD/gtk3" -t targets all | grep -E '\.gresource:' | cut -d: -f1 | sort -u) \
  || echo "WARN: partial build (broadwayd fpcast?) — check log"
mkdir -p "$BUILD/donor"
for f in broadwayd.js broadwayd.wasm; do
  [ -f "$BUILD/gtk3/gdk/broadway/$f" ] && cp "$BUILD/gtk3/gdk/broadway/$f" "$BUILD/donor/$f"
done
meson install -C "$BUILD/gtk3" --no-rebuild
# smoke test now links the bridge + daemon objects: the node test runs GDK
# against the real in-module broadwayd relay over pipe A (no browser yet).
daemon_objs "$TEST/daemon"
wasmtest gtk3 gtk3_test.c bridge/bytepipe.c bridge/bridge.c "$TEST/daemon"/*.o \
  -I"$SRC/gtk3/gdk/broadway" \
  $(pkg-config --static --cflags --libs gtk+-3.0) -lpthread
manifest gtk3 "$VER"
touch "$STAMPS/gtk3.ok"
