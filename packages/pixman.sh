#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pixman
VER=0.44.0
fetch "https://www.cairographics.org/releases/pixman-$VER.tar.gz"
extract_auto "pixman-$VER.tar.gz" pixman
me pixman -Dtests=disabled -Ddemos=disabled -Dlibpng=disabled -Dgtk=disabled
wasmtest pixman pixman_test.c $(pkg-config --static --cflags --libs pixman-1)
manifest pixman "$VER"
touch "$STAMPS/pixman.ok"
