#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gsl
VER=2.8
fetch "https://ftp.gnu.org/gnu/gsl/gsl-$VER.tar.gz"
extract_auto "gsl-$VER.tar.gz" gsl
# tarball's config.sub predates emscripten; refresh from system
cp /usr/share/misc/config.sub /usr/share/misc/config.guess "$SRC/gsl/"
ac gsl --disable-shared
wasmtest gsl gsl_test.c $(pkg-config --cflags --libs gsl)
manifest gsl "$VER"
touch "$STAMPS/gsl.ok"
