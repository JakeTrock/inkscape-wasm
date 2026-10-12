#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg fribidi
VER=1.0.16
# no release asset for this tag; use GitHub's auto-generated archive
fetch "https://github.com/fribidi/fribidi/archive/refs/tags/v$VER.tar.gz"
extract_auto "v$VER.tar.gz" fribidi
me fribidi -Dtests=false -Ddocs=false
wasmtest fribidi fribidi_test.c $(pkg-config --static --cflags --libs fribidi)
manifest fribidi "$VER"
touch "$STAMPS/fribidi.ok"
