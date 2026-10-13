#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg lib2geom
VER=1.4
[ -d "$SRC/lib2geom" ] || git clone --quiet https://gitlab.com/inkscape/lib2geom.git "$SRC/lib2geom"
git -C "$SRC/lib2geom" checkout --quiet "$VER"
cm lib2geom -D2GEOM_TESTING=OFF -DWITH_PROFILING=OFF \
            -DBUILD_SHARED_LIBS=OFF
# 2geom.pc's Libs omits its own deps (double-conversion, gsl) — Libs.private
# only; append them so non---static consumers (inkscape's pkg_check_modules) link them
sed -i 's|^Libs: -L\${libdir} -l2geom$|Libs: -L${libdir} -l2geom -lgsl -lgslcblas -ldouble-conversion|' "$SYSROOT/lib/pkgconfig/2geom.pc"
wasmtest lib2geom lib2geom_test.cpp -I"$SYSROOT/include/2geom-1.4.0" -L"$SYSROOT/lib" -l2geom -lgsl -lgslcblas -ldouble-conversion -lglib-2.0
manifest lib2geom "$VER"
touch "$STAMPS/lib2geom.ok"
