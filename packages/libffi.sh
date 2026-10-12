#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libffi
VER=3.8.0
fetch "https://github.com/libffi/libffi/releases/download/v$VER/libffi-$VER.tar.gz"
extract_auto "libffi-$VER.tar.gz" libffi
grep -q '\$stackAlloc' "$SRC/libffi/src/wasm/ffi.c" \
  || patch -d "$SRC/libffi" -p1 < "$PATCHES/libffi/em-js-deps-stack-funcs.patch"
ac libffi --disable-docs --disable-multi-os-directory
# make install skips the library on wasm32 hosts; install it by hand
cp "$BUILD/libffi/.libs/libffi.a" "$SYSROOT/lib/"
cp "$BUILD/libffi/libffi.pc" "$SYSROOT/lib/pkgconfig/"
# upstream names the file libffi.pc but consumers look up module 'ffi'
sed 's/^Name: libffi/Name: ffi/' "$BUILD/libffi/libffi.pc" > "$SYSROOT/lib/pkgconfig/ffi.pc"
wasmtest libffi libffi_test.c $(pkg-config --static --cflags --libs ffi)
manifest libffi "$VER"
touch "$STAMPS/libffi.ok"
