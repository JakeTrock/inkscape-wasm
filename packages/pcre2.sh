#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg pcre2
VER=10.42
fetch "https://github.com/PhilipHazel/pcre2/releases/download/pcre2-$VER/pcre2-$VER.tar.bz2"
extract_auto "pcre2-$VER.tar.bz2" pcre2
# 10.42 tarball has no meson.build (wrapdb patches it in); use CMake.
# CMAKE_POLICY_VERSION_MINIMUM: cmake 4 dropped <3.5 compat, pcre2 asks for 3.1
cm pcre2 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
         -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_PCRE2TEST=OFF \
         -DPCRE2_SUPPORT_JIT=OFF -DPCRE2_BUILD_DOCS=OFF \
         -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=ON \
         -DPCRE2_BUILD_PCRE2_32=ON -DPCRE2_BUILD_PCRE2_POSIX=ON \
         -DBUILD_SHARED_LIBS=OFF -DPCRE2_SHOW_REPORT=OFF
wasmtest pcre2 pcre2_test.c $(pkg-config --static --cflags --libs libpcre2-8)
manifest pcre2 "$VER"
touch "$STAMPS/pcre2.ok"
