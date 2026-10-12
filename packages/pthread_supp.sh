#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pthread_supp
# Supplement for emscripten non-mt libc's pthread stubs (see pthread_supp.c)
emcc -c packages/pthread_supp.c -o "$BUILD/pthread_supp.o" -O1 -ffunction-sections -fdata-sections
emar rcs "$SYSROOT/lib/libpthread.a" "$BUILD/pthread_supp.o"
wasmtest pthread_supp pthread_supp_test.c -lpthread
manifest pthread_supp custom
touch "$STAMPS/pthread_supp.ok"
