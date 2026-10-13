#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg lcms2
VER=2.16
fetch "https://downloads.sourceforge.net/project/lcms/lcms/$VER/lcms2-$VER.tar.gz"
extract_auto "lcms2-$VER.tar.gz" lcms2
cp /usr/share/misc/config.sub /usr/share/misc/config.guess "$SRC/lcms2/" # tarball predates emscripten
ac lcms2
wasmtest lcms2 lcms2_test.c -I"$SYSROOT/include" -L"$SYSROOT/lib" -llcms2
manifest lcms2 "$VER"
touch "$STAMPS/lcms2.ok"
