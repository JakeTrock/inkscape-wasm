#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg zlib
VER=1.3.1
fetch "https://github.com/madler/zlib/releases/download/v$VER/zlib-$VER.tar.gz"
extract_auto "zlib-$VER.tar.gz" zlib
# CMake route: zlib's CMakeLists generates two rules for libz.a when
# BUILD_SHARED_LIBS=OFF (zlib + zlibstatic) — ninja rejects duplicate outputs.
# zlib's own configure --static is the clean cross path.
mkdir -p "$BUILD/zlib"
( cd "$BUILD/zlib" && emconfigure "$SRC/zlib/configure" --prefix="$SYSROOT" --static )
( cd "$BUILD/zlib" && emmake make -j64 && emmake make install )
wasmtest zlib zlib_test.c -lz -L"$SYSROOT/lib"
manifest zlib "$VER"
touch "$STAMPS/zlib.ok"
