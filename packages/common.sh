#!/usr/bin/env bash
# packages/common.sh — shared build environment. Source it; never execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"; SYSROOT="$BUILD/sysroot"; STAMPS="$BUILD/stamps"
LOGS="$BUILD/logs"; SRC="$BUILD/src"; DL="$BUILD/dl"; TEST="$BUILD/test"
PATCHES="$ROOT/patches"
EMSDK_DIR="/data/jake/reversing/toki/emsdk"

source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
export PATH="$EMSDK_DIR:$EMSDK_DIR/upstream/emscripten:$PATH"

if command -v ccache >/dev/null 2>&1; then
  export CC="ccache emcc" CXX="ccache em++"
else
  export CC="emcc" CXX="em++"
fi
export AR="emar" RANLIB="emranlib"
# Flags are used by wasmtest() only — NOT exported, so build systems use
# their own flag logic (harfbuzz etc. deliberately build C++ w/o exceptions).
CFLAGS="-O1 -g1 -ffunction-sections -fdata-sections -sEMULATE_FUNCTION_POINTER_CASTS=1"
CXXFLAGS="$CFLAGS -fexceptions -frtti"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig:$SYSROOT/share/pkgconfig"
# NOTE: no PKG_CONFIG_SYSROOT_DIR — our .pc files use absolute prefixes, and
# sysroot-rewriting mangles host tool paths (glib_compile_resources etc.)
export CMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"

mkdir -p "$SYSROOT" "$STAMPS" "$LOGS" "$SRC" "$DL" "$TEST" "$PATCHES"

# Generated cross file: same as packages/emsdk.cross but with an absolute
# path to our pthread supplement (link lines carry no -L to the sysroot).
cat > "$BUILD/emsdk.cross" <<EOF
[binaries]
c = 'emcc'
cpp = 'em++'
ar = 'emar'
strip = 'emstrip'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true
cpp_args = ['-fexceptions', '-frtti']
# wasm strict function types: glib/gtk cast function pointers across arities
# everywhere (g_list_insert_sorted's 2-arg GCompareFunc → 3-arg GFunc etc.);
# emulation thunks are the systemic fix. LINK-ONLY setting — as a compile arg
# it trips -Werror=unused-command-line-argument in meson's sanity checks.
c_link_args = ['$SYSROOT/lib/libpthread.a', '-sEMULATE_FUNCTION_POINTER_CASTS=1', '-sSTACK_SIZE=8388608']
cpp_link_args = ['$SYSROOT/lib/libpthread.a', '-sEMULATE_FUNCTION_POINTER_CASTS=1', '-sSTACK_SIZE=8388608']

[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
EOF

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
    -DCMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" -DCMAKE_PREFIX_PATH="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-fexceptions -frtti" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache "$@"
  cmake --build "$BUILD/$name" -j 64
  cmake --install "$BUILD/$name"
}
me() { # me <name> [meson args...] — Meson build+install (cross file, static)
  local name="$1"; shift
  meson setup "$BUILD/$name" "$SRC/$name" --prefix="$SYSROOT" \
    --cross-file "$BUILD/emsdk.cross" --buildtype=release \
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
    -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=1 -sDEFAULT_TO_CXX=1 \
    -sSTACK_SIZE=8388608 \
    -sEXPORTED_FUNCTIONS=_malloc,_free,_main -sALLOW_TABLE_GROWTH=1 "${preload[@]}" \
    -I"$SYSROOT/include" -L"$SYSROOT/lib" "$@" "$SYSROOT/lib/libpthread.a" || return 1
  ( cd "$TEST" && node "$name.js" ) || return 1
  echo "PASS: $name"
}

daemon_objs() { # daemon_objs <outdir> — broadwayd relay sources to .o files
  # (compiled apart from consumers: they need -DGDK_COMPILATION, which must
  # not leak into app code that includes <gdk/gdk.h>)
  local out="$1" daemon="$SRC/gtk3/gdk/broadway" f
  mkdir -p "$out"
  for f in broadwayd broadway-server broadway-buffer broadway-output; do
    [ "$out/$f.o" -nt "$daemon/$f.c" ] && continue
    emcc -c "$daemon/$f.c" -o "$out/$f.o" -O1 -g1 -ffunction-sections -fdata-sections -fexceptions \
      -DGDK_COMPILATION \
      -I"$BUILD/gtk3" -I"$BUILD/gtk3/gdk/broadway" \
      -I"$SRC/gtk3" -I"$SRC/gtk3/gdk" -I"$SRC/gtk3/gdk/broadway" \
      -I"$SYSROOT/include" $(pkg-config --cflags gtk+-3.0) || return 1
  done
}

bridge_objs() { # bridge_objs <outdir> — bridge .c sources to .o files
  # (must be compiled as C even for C++ consumers: C++ rejects their
  # implicit void* casts)
  local out="$1" f
  mkdir -p "$out"
  for f in bytepipe bridge; do
    [ "$out/$f.o" -nt "$ROOT/bridge/$f.c" ] && continue
    emcc "$ROOT/bridge/$f.c" -c -o "$out/$f.o" -O1 -g1 -ffunction-sections -fdata-sections \
      -I"$BUILD/gtk3" -I"$BUILD/gtk3/gdk/broadway" \
      -I"$SRC/gtk3/gdk" -I"$SRC/gtk3/gdk/broadway" \
      -I"$SYSROOT/include" $(pkg-config --cflags gtk+-3.0) || return 1
  done
}
