#!/usr/bin/env bash
# packages/common.sh — shared build environment. Source it; never execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"; SYSROOT="$BUILD/sysroot"; STAMPS="$BUILD/stamps"
LOGS="$BUILD/logs"; SRC="$BUILD/src"; DL="$BUILD/dl"; TEST="$BUILD/test"
PATCHES="$ROOT/patches"
EMSDK_DIR="/data/jake/reversing/toki/emsdk"

source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1

if command -v ccache >/dev/null 2>&1; then
  export CC="ccache emcc" CXX="ccache em++"
else
  export CC="emcc" CXX="em++"
fi
export AR="emar" RANLIB="emranlib"
export CFLAGS="-O1 -g1 -ffunction-sections -fdata-sections -fexceptions"
export CXXFLAGS="$CFLAGS -frtti"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export CMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"

mkdir -p "$SYSROOT" "$STAMPS" "$LOGS" "$SRC" "$DL" "$TEST" "$PATCHES"

begin_pkg() { # begin_pkg <name> — exit 0 if already stamped
  if [ -e "$STAMPS/$1.ok" ]; then echo "$1: cached (rm build/stamps/$1.ok to rebuild)"; exit 0; fi
}
manifest() { echo "$1 $2" >> "$BUILD/manifest.txt"; } # manifest <real-name> <version>
fetch() { # fetch <url> — download to build/dl if missing
  local out="$DL/$(basename "$1")"
  [ -s "$out" ] || curl -fL --retry 3 -o "$out" "$1"
}
extract_auto() { # extract_auto <archive-basename> <name> — extract, rename top dir to build/src/<name>
  local archive="$1" name="$2" tmp="$SRC/.$2.extract.$$"
  if [ ! -d "$SRC/$name" ]; then
    mkdir -p "$tmp"; tar -xf "$DL/$archive" -C "$tmp"
    mv "$tmp"/*/ "$SRC/$name"; rmdir "$tmp"
  fi
}
cm() { # cm <name> [cmake args...] — CMake+Ninja build+install
  local name="$1"; shift
  cmake -S "$SRC/$name" -B "$BUILD/$name" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache "$@"
  cmake --build "$BUILD/$name" -j 64
  cmake --install "$BUILD/$name"
}
me() { # me <name> [meson args...] — Meson build+install (cross file, static)
  local name="$1"; shift
  meson setup "$BUILD/$name" "$SRC/$name" --prefix="$SYSROOT" \
    --cross-file "$ROOT/packages/emsdk.cross" --buildtype=release \
    --default-library=static "$@"
  meson compile -C "$BUILD/$name" -j 64
  meson install -C "$BUILD/$name"
}
ac() { # ac <name> [configure args...] — autotools build via emconfigure
  local name="$1"; shift
  mkdir -p "$BUILD/$name"
  ( cd "$BUILD/$name"
    emconfigure "$SRC/$name/configure" --prefix="$SYSROOT" \
      --host=wasm32-emscripten --disable-shared --enable-static "$@" )
  ( cd "$BUILD/$name" && emmake make -j64 && emmake make install )
}
wasmtest() { # wasmtest <name> <src-under-tests/lib> [link args...]
  local name="$1" src="$ROOT/tests/lib/$2"; shift 2
  local comp=emcc; case "$src" in *.cpp|*.cc) comp=em++;; esac
  local preload=()
  [ -d "$ROOT/tests/fixtures" ] && preload=(--preload-file "$ROOT/tests/fixtures@/fixtures")
  "$comp" "$src" -o "$TEST/$name.js" $CXXFLAGS \
    -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=1 "${preload[@]}" "$@"
  ( cd "$TEST" && node "$name.js" )
  echo "PASS: $name"
}
