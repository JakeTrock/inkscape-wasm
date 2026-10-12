#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg harfbuzz
VER=14.6.0
fetch "https://github.com/harfbuzz/harfbuzz/releases/download/$VER/harfbuzz-$VER.tar.xz"
extract_auto "harfbuzz-$VER.tar.xz" harfbuzz
grep -q "!= 'emscripten'" "$SRC/harfbuzz/meson.build" \
  || patch -d "$SRC/harfbuzz" -p1 < "$PATCHES/harfbuzz/no-threads.patch"
me harfbuzz -Dtests=disabled -Ddocs=disabled -Dutilities=disabled \
  -Dicu=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
  -Dfreetype=enabled -Dintrospection=disabled
wasmtest harfbuzz harfbuzz_test.c $(pkg-config --static --cflags --libs harfbuzz)
manifest harfbuzz "$VER"
touch "$STAMPS/harfbuzz.ok"
