#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg glibmm
VER=2.66.7
fetch "https://download.gnome.org/sources/glibmm/2.66/glibmm-$VER.tar.xz"
extract_auto "glibmm-$VER.tar.xz" glibmm
# tarball has no generated configure; use its meson build.
# Libraries only: glibmm's test executables get meson's -pthread injection.
meson setup "$BUILD/glibmm" "$SRC/glibmm" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbuild-documentation=false -Dbuild-examples=false -Dmsvc14x-parallel-installable=false
ninja -C "$BUILD/glibmm" -j 64 glib/glibmm/libglibmm-2.4.a gio/giomm/libgiomm-2.4.a tools/extra_defs_gen/libglibmm_generate_extra_defs-2.4.a
meson install -C "$BUILD/glibmm" --no-rebuild
# no .pc upstream; pangomm/gtkmm find this via pkg-config library lookup
cat > "$SYSROOT/lib/pkgconfig/glibmm_generate_extra_defs-2.4.pc" <<EOF
prefix=$SYSROOT
libdir=\${prefix}/lib

Name: glibmm_generate_extra_defs-2.4
Description: glibmm extra defs generator helper lib
Version: $VER
Requires: glibmm-2.4
Libs: -L\${libdir} -lglibmm_generate_extra_defs-2.4
EOF
wasmtest glibmm glibmm_test.cpp $(pkg-config --cflags --libs glibmm-2.4)
manifest glibmm "$VER"
touch "$STAMPS/glibmm.ok"
