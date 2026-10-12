#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gtkmm
VER=3.24.9
fetch "https://download.gnome.org/sources/gtkmm/3.24/gtkmm-$VER.tar.xz"
extract_auto "gtkmm-$VER.tar.xz" gtkmm
patch -d "$SRC/gtkmm" -p1 -R --dry-run -f < "$PATCHES/gtkmm/no-extra-defs-tool.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtkmm" -p1 < "$PATCHES/gtkmm/no-extra-defs-tool.patch"
# tarball ships meson (no generated configure); libraries only
meson setup "$BUILD/gtkmm" "$SRC/gtkmm" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-documentation=false -Dbuild-demos=false -Dbuild-tests=false \
  -Dbuild-x11-api=false -Dmsvc14x-parallel-installable=false
ninja -C "$BUILD/gtkmm" -j 64 gdk/gdkmm/libgdkmm-3.0.a gtk/gtkmm/libgtkmm-3.0.a
meson install -C "$BUILD/gtkmm" --no-rebuild
wasmtest gtkmm gtkmm_test.cpp $(pkg-config --cflags --libs gtkmm-3.0)
manifest gtkmm "$VER"
touch "$STAMPS/gtkmm.ok"
