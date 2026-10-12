#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg cairomm
VER=1.14.4
# GNOME pruned the 1.14 dir; canonical home is cairographics.org
fetch "https://www.cairographics.org/releases/cairomm-$VER.tar.xz"
extract_auto "cairomm-$VER.tar.xz" cairomm
# tarball ships meson (no generated configure); libraries only
meson setup "$BUILD/cairomm" "$SRC/cairomm" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-documentation=false -Dbuild-examples=false -Dbuild-tests=false
ninja -C "$BUILD/cairomm" -j 64 cairomm/libcairomm-1.0.a
meson install -C "$BUILD/cairomm" --no-rebuild
wasmtest cairomm cairomm_test.cpp $(pkg-config --cflags --libs cairomm-1.0)
manifest cairomm "$VER"
touch "$STAMPS/cairomm.ok"
