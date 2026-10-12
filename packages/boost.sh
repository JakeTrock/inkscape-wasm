#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg boost
VER=1.86.0
fetch "https://archives.boost.io/release/$VER/source/boost_1_86_0.tar.gz"
extract_auto "boost_1_86_0.tar.gz" boost
mkdir -p "$SYSROOT/include"
cp -r "$SRC/boost/boost" "$SYSROOT/include/"
wasmtest boost boost_test.cpp -I"$SYSROOT/include"
manifest boost "$VER"
touch "$STAMPS/boost.ok"
