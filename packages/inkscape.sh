#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg inkscape
VER=1.4.4

[ -d "$SRC/inkscape-1.4.4" ] || git clone --quiet --depth 1 --branch INKSCAPE_1_4_4 \
  https://gitlab.com/inkscape/inkscape.git "$SRC/inkscape-1.4.4"
# src/3rdparty submodules are unconditional in cmake (uemf/croco/depixelize/
# adaptagrams/autotrace); 2geom comes too (unused here with INTERNAL_2GEOM=OFF,
# needed by the native golden build in task 4)
git -C "$SRC/inkscape-1.4.4" submodule update --init --quiet -- src/3rdparty

# patches (reverse-dry-run guards, gtk3.sh pattern)
for p in broadway-env libcxx-compat no-boost-stacktrace no-boost-stacktrace-runtime no-asio-threadpool; do
  patch -d "$SRC/inkscape-1.4.4" -p1 -R --dry-run -f < "$PATCHES/inkscape/$p.patch" >/dev/null 2>&1 \
    || patch -d "$SRC/inkscape-1.4.4" -p1 < "$PATCHES/inkscape/$p.patch"
done

# bridge + in-module daemon objects: libgdk's broadway backend references them.
# Archived, not passed as loose .o files: global linker flags reach every
# cmake try_compile, and loose objects get linked eagerly (bridge.o needs
# glib symbols a minimal test program doesn't have) — archives are pulled
# only when a lib (libgdk) references their symbols.
daemon_objs "$TEST/daemon"
bridge_objs "$TEST"
emar cr "$TEST/libinkbridge.a" "$TEST/bytepipe.o" "$TEST/bridge.o" \
  "$TEST/daemon/broadwayd.o" "$TEST/daemon/broadway-server.o" \
  "$TEST/daemon/broadway-buffer.o" "$TEST/daemon/broadway-output.o"

# stage the runtime FS: trimmed share/ tree + fonts + writable profile dir,
# mounted at / by the preload below
FS="$BUILD/inkscape-fs"
if [ ! -d "$FS/inkscape/share/ui" ]; then
  rm -rf "$FS"
  mkdir -p "$FS/inkscape/share" "$FS/fixtures" "$FS/home/web_user"
  for d in attributes filters fontcollections icons keys markers paint \
           palettes screens symbols templates themes ui; do
    [ -d "$SRC/inkscape-1.4.4/share/$d" ] && cp -r "$SRC/inkscape-1.4.4/share/$d" "$FS/inkscape/share/"
  done
  cp "$ROOT/tests/fixtures/fonts.conf" "$FS/fixtures/"
  cp "$ROOT"/tests/fixtures/*.ttf "$FS/fixtures/"
fi

cmake -S "$SRC/inkscape-1.4.4" -B "$BUILD/inkscape" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
  -DCMAKE_FIND_ROOT_PATH="$SYSROOT" -DCMAKE_PREFIX_PATH="$SYSROOT" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/inkscape \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_C_FLAGS="-fexceptions -sEMULATE_FUNCTION_POINTER_CASTS=1" \
  -DCMAKE_CXX_FLAGS="-fexceptions -frtti -sEMULATE_FUNCTION_POINTER_CASTS=1" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$TEST -linkbridge -L$SYSROOT/lib -sSTACK_SIZE=8388608 \
    -sALLOW_MEMORY_GROWTH=1 -sALLOW_TABLE_GROWTH=1 -sEMULATE_FUNCTION_POINTER_CASTS=1 \
    -sMODULARIZE=1 -sEXPORT_NAME=Module \
    -sEXPORTED_RUNTIME_METHODS=HEAPU8,callMain,FS -sINITIAL_MEMORY=536870912 \
    --preload-file $FS@/" \
  -DBUILD_TESTING=OFF -DENABLE_BINRELOC=OFF \
  -DENABLE_POPPLER=OFF -DENABLE_POPPLER_CAIRO=OFF \
  -DWITH_IMAGE_MAGICK=OFF -DWITH_GRAPHICS_MAGICK=OFF \
  -DWITH_LIBCDR=OFF -DWITH_LIBVISIO=OFF -DWITH_LIBWPG=OFF \
  -DWITH_GSPELL=OFF -DWITH_GSOURCEVIEW=OFF \
  -DWITH_NLS=OFF -DWITH_X11=OFF -DWITH_OPENMP=OFF -DWITH_GNU_READLINE=OFF \
  -DWITH_INTERNAL_2GEOM=OFF -DWITH_SVG2=ON -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD/inkscape" -j 64 --target inkscape

manifest inkscape "$VER"
touch "$STAMPS/inkscape.ok"
