#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg cairo
VER=1.18.2
fetch "https://www.cairographics.org/releases/cairo-$VER.tar.xz"
extract_auto "cairo-$VER.tar.xz" cairo
grep -q "!= 'emscripten' and cc.links" "$SRC/cairo/meson.build" \
  || patch -d "$SRC/cairo" -p1 < "$PATCHES/cairo/no-pthreads-emscripten.patch"
# Library only: meson injects -pthread into emscripten *executables*, which
# kills cairo's uninstalled util/ tools; we don't need them.
meson setup "$BUILD/cairo" "$SRC/cairo" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dtests=disabled -Dspectre=disabled -Dsymbol-lookup=disabled \
  -Dc_args=-DCAIRO_NO_MUTEX=1 \
  -Dxlib=disabled -Dxcb=disabled -Dquartz=disabled \
  -Dzlib=enabled -Dpng=enabled -Dfreetype=enabled -Dfontconfig=enabled \
  -Dglib=enabled
ninja -C "$BUILD/cairo" -j 64 src/libcairo.a util/cairo-gobject/libcairo-gobject.a \
  util/cairo-script/libcairo-script-interpreter.a
meson install -C "$BUILD/cairo" --no-rebuild
wasmtest cairo cairo_test.c $(pkg-config --static --cflags --libs cairo)
manifest cairo "$VER"
touch "$STAMPS/cairo.ok"
