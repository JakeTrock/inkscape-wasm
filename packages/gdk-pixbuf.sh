#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gdk-pixbuf
VER=2.44.4
fetch "https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-$VER.tar.xz"
extract_auto "gdk-pixbuf-$VER.tar.xz" gdk-pixbuf
grep -q "!= 'emscripten')" "$SRC/gdk-pixbuf/gdk-pixbuf/meson.build" \
  || patch -d "$SRC/gdk-pixbuf" -p1 < "$PATCHES/gdk-pixbuf/no-tool-install-emscripten.patch"
# Libraries only (tools fail to link on emscripten, as with pango/cairo/glib);
# man/journal/intspection off; png+jpeg built-in, tiff off.
meson setup "$BUILD/gdk-pixbuf" "$SRC/gdk-pixbuf" --prefix="$SYSROOT" \
  --cross-file "$ROOT/packages/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dtests=false -Ddocumentation=false -Dintrospection=disabled -Dman=false \
  -Dinstalled_tests=false -Dgio_sniffing=false -Drelocatable=false -Dthumbnailer=disabled \
  -Dbuiltin_loaders=png,jpeg \
  -Dpng=enabled -Djpeg=enabled -Dtiff=disabled -Dothers=disabled -Dgif=disabled
ninja -C "$BUILD/gdk-pixbuf" -j 64 gdk-pixbuf/libgdk_pixbuf-2.0.a \
  subprojects/libjpeg-turbo-2.1.2/libjpeg.a
meson install -C "$BUILD/gdk-pixbuf" --no-rebuild
wasmtest gdk-pixbuf gdkpixbuf_test.c $(pkg-config --static --cflags --libs gdk-pixbuf-2.0) -lpthread
manifest gdk-pixbuf "$VER"
touch "$STAMPS/gdk-pixbuf.ok"
