#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg gtk3
VER=3.24.43
fetch "https://download.gnome.org/sources/gtk+/3.24/gtk+-$VER.tar.xz"
extract_auto "gtk+-$VER.tar.xz" gtk3
grep -q "to-pixdata" "$SRC/gtk3/gtk/gen-gtk-gresources-xml.py" \
  && patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-to-pixdata.patch"
grep -q "!= 'emscripten'" "$SRC/gtk3/gtk/meson.build" \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-tool-install-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/no-print-backend-module.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/no-print-backend-module.patch"
# Libraries only: gtk's own executables (broadwayd aside) can't link on
# emscripten (meson injects -pthread into exe links). broadwayd itself is
# reused as source in leg B, not linked here.
meson setup "$BUILD/gtk3" "$SRC/gtk3" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dbroadway_backend=true -Dx11_backend=false -Dwayland_backend=false \
  -Dwin32_backend=false -Dquartz_backend=false \
  -Dgtk_doc=false -Dman=false -Dintrospection=false \
  -Dtests=false -Ddemos=false -Dexamples=false -Dinstalled_tests=false \
  -Dbuiltin_immodules=all \
  -Dcolord=no -Dprint_backends=file -Dcloudproviders=false -Dtracker3=false
# Libraries + broadwayd only (leg-B donor); the other gtk tools are not
# installed (see no-tool-install patch) and can't link on emscripten.
# Full build (locale gresources etc. are install inputs); tools link against
# the pthread/DNS/ftw supplement via the cross-file link args.
ninja -C "$BUILD/gtk3" -j 64
meson install -C "$BUILD/gtk3" --no-rebuild
wasmtest gtk3 gtk3_test.c $(pkg-config --static --cflags --libs gtk+-3.0) -lpthread
manifest gtk3 "$VER"
touch "$STAMPS/gtk3.ok"
