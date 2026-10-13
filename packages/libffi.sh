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
# NOTE: link WITHOUT fpcast — emscripten's JS ffi_call_js calls table entries
# directly, and fpcast thunks are not transparent to that. Constraint for the
# final link: ffi_call must not run at runtime (gtk signal closures use direct
# marshals, so the stack is unaffected; see findings.md).
NOFPC="${CXXFLAGS/-sEMULATE_FUNCTION_POINTER_CASTS=1/}"
emcc tests/lib/libffi_test.c -o "$TEST/libffi.js" $NOFPC \
  -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=1 -sEXPORTED_FUNCTIONS=_malloc,_free,_main \
  -sALLOW_TABLE_GROWTH=1 -I"$SYSROOT/include" -L"$SYSROOT/lib" \
  $(pkg-config --static --cflags --libs ffi) "$SYSROOT/lib/libpthread.a" \
  && ( cd "$TEST" && node libffi.js )
manifest libffi "$VER"
touch "$STAMPS/libffi.ok"
