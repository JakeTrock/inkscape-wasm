#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libpng
VER=1.6.45
fetch "https://github.com/pnggroup/libpng/archive/refs/tags/v$VER.tar.gz"
extract_auto "v$VER.tar.gz" libpng
cm libpng -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
wasmtest libpng libpng_test.c $(pkg-config --static --cflags --libs libpng)
manifest libpng "$VER"
touch "$STAMPS/libpng.ok"
