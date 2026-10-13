#!/usr/bin/env bash
# T4 gate: lib2geom's own test suite (googletest) built for wasm, run in node.
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh

[ -f "$STAMPS/check-4.ok" ] && { echo "check-4 cached"; exit 0; }

GTEST_VER=1.15.2
GTEST_ROOT="$BUILD/test/gtest-root"
TDIR="$BUILD/test/2geom-tests"

# 1. googletest — test-only install outside the sysroot
if [ ! -f "$GTEST_ROOT/lib/libgtest.a" ]; then
  fetch "https://github.com/google/googletest/archive/refs/tags/v$GTEST_VER.tar.gz"
  extract_auto "v$GTEST_VER.tar.gz" googletest
  cmake -S "$SRC/googletest" -B "$BUILD/test/gtest" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$GTEST_ROOT" \
    -DCMAKE_CXX_FLAGS="-fexceptions -frtti" \
    -Dgtest_build_tests=OFF -Dgmock_build_tests=OFF -DBUILD_GMOCK=OFF \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
  cmake --build "$BUILD/test/gtest" -j 64
  cmake --install "$BUILD/test/gtest"
fi

# 2. lib2geom with tests enabled — separate dir, sysroot lib untouched
if [ ! -f "$TDIR/tests/point-test.js" ]; then
  cmake -S "$SRC/lib2geom" -B "$TDIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT" -DCMAKE_PREFIX_PATH="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -D2GEOM_TESTING=ON -DWITH_PROFILING=OFF \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_FLAGS="-fexceptions -frtti -sEMULATE_FUNCTION_POINTER_CASTS=1" \
    -DCMAKE_C_FLAGS="-fexceptions -sEMULATE_FUNCTION_POINTER_CASTS=1" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$SYSROOT/lib -O0 -sSTACK_SIZE=8388608 -sALLOW_MEMORY_GROWTH=1 -sALLOW_TABLE_GROWTH=1 -sEMULATE_FUNCTION_POINTER_CASTS=1" \
    -DGTEST_INCLUDE_DIR="$GTEST_ROOT/include" \
    -DGTEST_LIBRARY="$GTEST_ROOT/lib/libgtest.a" \
    -DGTEST_MAIN_LIBRARY="$GTEST_ROOT/lib/libgtest_main.a"
  cmake --build "$TDIR" -j 64
fi

# 3. run every test binary in node; xfail.txt allowlists platform failures
fail=0
for js in "$TDIR"/tests/*-test.js; do
  t="$(basename "$js" .js)"
  if timeout 120 node "$js" > "$LOGS/t4-$t.log" 2>&1; then
    echo "PASS $t"
  elif grep -qx "$t" "$ROOT/tests/t4/xfail.txt" 2>/dev/null; then
    echo "XFAIL $t (allowlisted)"
  else
    echo "FAIL $t (log: build/logs/t4-$t.log)"
    fail=1
  fi
done

[ "$fail" = 0 ] || exit 1
mkdir -p "$STAMPS"
touch "$STAMPS/check-4.ok"
echo "PASS: check-4"
