#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pango
VER=1.56.4
fetch "https://download.gnome.org/sources/pango/1.56/pango-$VER.tar.xz"
extract_auto "pango-$VER.tar.xz" pango
grep -q "!= 'emscripten'" "$SRC/pango/utils/meson.build" \
  || patch -d "$SRC/pango" -p1 < "$PATCHES/pango/no-tool-install-emscripten.patch"
# Libraries only: pango's tools (pango-view etc.) fail to link on emscripten
# (C links miss libc++ which harfbuzz's std::mutex fallback needs).
meson setup "$BUILD/pango" "$SRC/pango" --prefix="$SYSROOT" \
  --cross-file "$ROOT/packages/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-testsuite=false -Dbuild-examples=false -Ddocumentation=false -Dintrospection=disabled \
  -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled \
  -Dlibthai=disabled -Dsysprof=disabled -Dman-pages=false
ninja -C "$BUILD/pango" -j 64 \
  pango/libpango-1.0.a pango/libpangoft2-1.0.a pango/libpangocairo-1.0.a
meson install -C "$BUILD/pango" --no-rebuild
wasmtest pango pango_test.c $(pkg-config --static --cflags --libs pangocairo) -lpthread
manifest pango "$VER"
touch "$STAMPS/pango.ok"
