#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg fontconfig
VER=2.16.0
fetch "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$VER.tar.xz"
extract_auto "fontconfig-$VER.tar.xz" fontconfig
patch -N -d "$SRC/fontconfig" -p1 < "$PATCHES/fontconfig/no-threads.patch"
# freetype/expat are found via pkg-config (not meson options in 2.16)
me fontconfig -Ddoc=disabled -Ddoc-txt=disabled -Ddoc-man=disabled \
  -Ddoc-pdf=disabled -Ddoc-html=disabled -Dnls=disabled -Dtests=disabled \
  -Dtools=disabled -Dcache-build=disabled -Dxml-backend=expat \
  -Ddefault-fonts-dirs=[] -Dadditional-fonts-dirs=[]
wasmtest fontconfig fontconfig_test.c $(pkg-config --static --cflags --libs fontconfig)
manifest fontconfig "$VER"
touch "$STAMPS/fontconfig.ok"
