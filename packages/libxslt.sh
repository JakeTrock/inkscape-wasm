#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libxslt
VER=1.1.42
fetch "https://download.gnome.org/sources/libxslt/1.1/libxslt-$VER.tar.xz"
extract_auto "libxslt-$VER.tar.xz" libxslt
# 1.1.42 ships autotools (no meson). PATH puts OUR xml2-config first (the
# host's is 2.15 — version skew). LDFLAGS for tool links.
export PATH="$SYSROOT/bin:$PATH"
LDFLAGS="-L$SYSROOT/lib" ac libxslt --without-python --without-crypto --without-profiler
wasmtest libxslt libxslt_test.c $(pkg-config --cflags --libs libxslt)
manifest libxslt "$VER"
touch "$STAMPS/libxslt.ok"
