#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg sigcpp
VER=2.12.1
fetch "https://download.gnome.org/sources/libsigc%2B%2B/2.12/libsigc%2B%2B-$VER.tar.xz"
extract_auto "libsigc%2B%2B-$VER.tar.xz" sigcpp
# 2.12 tarball ships no generated configure; use its meson build.
me sigcpp -Dbuild-documentation=false -Dbuild-examples=false \
  -Dbuild-tests=false -Dvalidation=false -Dbenchmark=false
wasmtest sigcpp sigcpp_test.cpp $(pkg-config --cflags --libs sigc++-2.0)
manifest libsigc++ "2.12.1"
touch "$STAMPS/sigcpp.ok"
