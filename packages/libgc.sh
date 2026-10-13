#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libgc
VER=8.2.8
fetch "https://github.com/ivmai/bdwgc/releases/download/v$VER/gc-$VER.tar.gz"
extract_auto "gc-$VER.tar.gz" libgc
ac libgc --disable-threads --disable-shared --disable-gcj-support \
         --disable-java-finalization --enable-munmap=0
# upstream installs bdw-gc.pc; Inkscape looks up module 'gc'
cp "$SYSROOT/lib/pkgconfig/bdw-gc.pc" "$SYSROOT/lib/pkgconfig/gc.pc"
set +e
wasmtest libgc libgc_test.c $(pkg-config --cflags --libs gc) > "$LOGS/libgc-rung1.log" 2>&1
rc=$?
set -e
if [ "$rc" = 0 ]; then
  manifest "libgc (real)" "$VER"
else
  echo "libgc rung 1 FAILED (rc=$rc) — continue the ladder per plan Task 18 Step 3" >&2
  exit 1
fi
touch "$STAMPS/libgc.ok"
