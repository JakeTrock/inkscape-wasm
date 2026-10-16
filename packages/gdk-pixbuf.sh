#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gdk-pixbuf
VER=2.44.4
fetch "https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-$VER.tar.xz"
extract_auto "gdk-pixbuf-$VER.tar.xz" gdk-pixbuf
grep -q "!= 'emscripten')" "$SRC/gdk-pixbuf/gdk-pixbuf/meson.build" \
  || patch -d "$SRC/gdk-pixbuf" -p1 < "$PATCHES/gdk-pixbuf/no-tool-install-emscripten.patch"
patch -d "$SRC/gdk-pixbuf" -p1 -R --dry-run -f < "patches/gdk-pixbuf/iface-init-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gdk-pixbuf" -p1 < "patches/gdk-pixbuf/iface-init-signatures.patch"
# wasm: drop 3 unused params so table-resident line funcs fit fpcast-emu's limit
patch -d "$SRC/gdk-pixbuf" -p1 -R --dry-run -f < "patches/gdk-pixbuf/pixops-line-func-params.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gdk-pixbuf" -p1 < "patches/gdk-pixbuf/pixops-line-func-params.patch"
patch -d "$SRC/gdk-pixbuf" -p1 -R --dry-run -f < "patches/gdk-pixbuf/svg-png-fallback-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gdk-pixbuf" -p1 < "patches/gdk-pixbuf/svg-png-fallback-emscripten.patch"
# Libraries only (tools fail to link on emscripten, as with pango/cairo/glib);
# man/journal/intspection off; png+jpeg built-in, tiff off.
# jpeg: the subproject-built libjpeg is installed in the sysroot (17:52 build),
# meson finds it via pkg-config, so no explicit subproject target anymore.
meson setup "$BUILD/gdk-pixbuf" "$SRC/gdk-pixbuf" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dtests=false -Ddocumentation=false -Dintrospection=disabled -Dman=false \
  -Dinstalled_tests=false -Dgio_sniffing=false -Drelocatable=false -Dthumbnailer=disabled \
  -Dbuiltin_loaders=png,jpeg \
  -Dpng=enabled -Djpeg=enabled -Dtiff=disabled -Dothers=disabled -Dgif=disabled
ninja -C "$BUILD/gdk-pixbuf" -j 64 gdk-pixbuf/libgdk_pixbuf-2.0.a
meson install -C "$BUILD/gdk-pixbuf" --no-rebuild
wasmtest gdk-pixbuf gdkpixbuf_test.c $(pkg-config --static --cflags --libs gdk-pixbuf-2.0) -lpthread
manifest gdk-pixbuf "$VER"
touch "$STAMPS/gdk-pixbuf.ok"
