#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg boost
VER=1.86.0
fetch "https://archives.boost.io/release/$VER/source/boost_1_86_0.tar.gz"
extract_auto "boost_1_86_0.tar.gz" boost
mkdir -p "$SYSROOT/include"
cp -r "$SRC/boost/boost" "$SYSROOT/include/"
# Compiled libs Inkscape needs: boost_filesystem (REQUIRED) + stacktrace
# (its optional backtrace variant never resolves on wasm; the basic variant
# is the fallback). b2 understands the emscripten toolset.
(
  cd "$SRC/boost"
  [ -f b2 ] || ./bootstrap.sh --with-libraries=filesystem,stacktrace
  echo "using emscripten : : em++ ;" > user-config.jam
  rm -rf bin.v2
  # boost's emscripten toolset maps <exception-handling-method>js to
  # -fexceptions (our stack's EH); with no method set clang emits native
  # wasm-EH (__gxx_wasm_personality_v0) that our links reject.
  ./b2 toolset=emscripten link=static threading=multi address-model=32 \
     exception-handling=on exception-handling-method=js rtti=on \
     --with-filesystem --with-stacktrace \
     boost.stacktrace.from_exception=off \
     --prefix="$SYSROOT" install -j64
)
wasmtest boost boost_fs_test.cpp -I"$SYSROOT/include" -L"$SYSROOT/lib" \
  -lboost_filesystem
manifest boost "$VER"
touch "$STAMPS/boost.ok"
