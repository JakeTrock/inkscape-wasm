#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg expat
VER=2.6.4
fetch "https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-$VER.tar.gz"
extract_auto "expat-$VER.tar.gz" expat
cm expat -DEXPAT_SHARED_LIBS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF
wasmtest expat expat_test.c -lexpat
manifest expat "$VER"
touch "$STAMPS/expat.ok"
