#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg zlib
VER=1.3.1
fetch "https://github.com/madler/zlib/releases/download/v$VER/zlib-$VER.tar.gz"
extract_auto "zlib-$VER.tar.gz" zlib
cm zlib
wasmtest zlib zlib_test.c -lz -L"$SYSROOT/lib"
manifest zlib "$VER"
touch "$STAMPS/zlib.ok"
