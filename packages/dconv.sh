#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg dconv
VER=3.3.0
fetch "https://github.com/google/double-conversion/archive/refs/tags/v$VER.tar.gz"
extract_auto "double-conversion-$VER.tar.gz" dconv
cm dconv -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_TESTING=OFF
wasmtest dconv dconv_test.cpp $(pkg-config --cflags --libs double-conversion)
manifest double-conversion "$VER"
touch "$STAMPS/dconv.ok"
