#!/usr/bin/env bash
# Native Inkscape 1.4.4 — the golden-image generator (same source tree and
# version as the wasm build; system libs). Not part of the sysroot.
set -euo pipefail
cd "$(dirname "$0")/.." ; source packages/common.sh

# common.sh exports the wasm cross environment; cmake also reads the
# CMAKE_TOOLCHAIN_FILE env var, which silently cross-compiles this "native"
# build — sanitize before configuring.
unset CC CXX AR RANLIB CMAKE_TOOLCHAIN_FILE PKG_CONFIG_PATH PKG_CONFIG_LIBDIR

[ -e "$STAMPS/native-inkscape.ok" ] && { echo "native-inkscape: cached"; exit 0; }

# build deps (same REQUIRED set the wasm configure validated, minus emscripten)
sudo -n apt-get install -y -qq \
  libgtkmm-3.0-dev libgsl-dev libboost-filesystem-dev libpotrace-dev \
  liblcms2-dev libdouble-conversion-dev libxml2-dev libxslt1-dev \
  libharfbuzz-dev libgc-dev libepoxy-dev libpng-dev libjpeg-dev \
  ninja-build cmake >/dev/null

git -C "$SRC/inkscape-1.4.4" submodule update --init --quiet -- src/3rdparty

cmake -S "$SRC/inkscape-1.4.4" -B "$BUILD/native/inkscape" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$BUILD/native/prefix" \
  -DBUILD_TESTING=OFF -DENABLE_BINRELOC=OFF \
  -DENABLE_POPPLER=OFF -DENABLE_POPPLER_CAIRO=OFF \
  -DWITH_IMAGE_MAGICK=OFF -DWITH_GRAPHICS_MAGICK=OFF \
  -DWITH_LIBCDR=OFF -DWITH_LIBVISIO=OFF -DWITH_LIBWPG=OFF \
  -DWITH_GSPELL=OFF -DWITH_GSOURCEVIEW=OFF \
  -DWITH_NLS=OFF -DWITH_X11=OFF -DWITH_OPENMP=OFF -DWITH_GNU_READLINE=OFF \
  -DWITH_INTERNAL_2GEOM=ON -DWITH_SVG2=ON -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD/native/inkscape" -j 64 --target inkscape

BIN="$BUILD/native/inkscape/bin/inkscape"
"$BIN" --version | head -1
touch "$STAMPS/native-inkscape.ok"
