#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg potrace
VER=1.16
fetch "https://potrace.sourceforge.net/download/potrace-$VER.tar.gz"
extract_auto "potrace-$VER.tar.gz" potrace
cp /usr/share/misc/config.sub /usr/share/misc/config.guess "$SRC/potrace/" # tarball predates emscripten
# Library + headers only satisfy Inkscape's find_package(Potrace REQUIRED).
# (Leg A findings: the lib builds+links cleanly on wasm; tracing behavior is
# NOT gated — potrace_trace returned NULL paths in the wasm smoke test.)
ac potrace --with-libpotrace
wasmtest potrace potrace_test.c -I"$SYSROOT/include" -L"$SYSROOT/lib" -lpotrace
manifest potrace "$VER"
touch "$STAMPS/potrace.ok"
