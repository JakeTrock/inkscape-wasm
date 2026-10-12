#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pangomm
VER=2.46.3
fetch "https://download.gnome.org/sources/pangomm/2.46/pangomm-$VER.tar.xz"
extract_auto "pangomm-$VER.tar.xz" pangomm
patch -d "$SRC/pangomm" -p1 -R --dry-run -f < "$PATCHES/pangomm/no-extra-defs-tool.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/pangomm" -p1 < "$PATCHES/pangomm/no-extra-defs-tool.patch"
# tarball ships meson (no generated configure); libraries only
meson setup "$BUILD/pangomm" "$SRC/pangomm" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-documentation=false -Dmsvc14x-parallel-installable=false
ninja -C "$BUILD/pangomm" -j 64 pango/pangomm/libpangomm-1.4.a
meson install -C "$BUILD/pangomm" --no-rebuild
wasmtest pangomm pangomm_test.cpp $(pkg-config --cflags --libs pangomm-1.4)
manifest pangomm "$VER"
touch "$STAMPS/pangomm.ok"
