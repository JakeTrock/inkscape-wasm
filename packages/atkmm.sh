#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg atkmm
VER=2.28.4
fetch "https://download.gnome.org/sources/atkmm/2.28/atkmm-$VER.tar.xz"
extract_auto "atkmm-$VER.tar.xz" atkmm
patch -d "$SRC/atkmm" -p1 -R --dry-run -f < "$PATCHES/atkmm/no-extra-defs-tool.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/atkmm" -p1 < "$PATCHES/atkmm/no-extra-defs-tool.patch"
# tarball ships meson (no generated configure); libraries only
meson setup "$BUILD/atkmm" "$SRC/atkmm" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-documentation=false -Dmsvc14x-parallel-installable=false
ninja -C "$BUILD/atkmm" -j 64 atk/atkmm/libatkmm-1.6.a
meson install -C "$BUILD/atkmm" --no-rebuild
wasmtest atkmm atkmm_test.cpp $(pkg-config --cflags --libs atkmm-1.6)
manifest atkmm "$VER"
touch "$STAMPS/atkmm.ok"
