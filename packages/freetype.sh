#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg freetype
VER=2.13.3
fetch "https://download.savannah.gnu.org/releases/freetype/freetype-$VER.tar.gz"
extract_auto "freetype-$VER.tar.gz" freetype
cm freetype -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=ON \
            -DFT_REQUIRE_PNG=ON -DFT_REQUIRE_ZLIB=ON -DFT_BUILD_TESTS=OFF
wasmtest freetype freetype_test.c $(pkg-config --static --cflags --libs freetype2)
manifest freetype "$VER"
touch "$STAMPS/freetype.ok"
