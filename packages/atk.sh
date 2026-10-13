#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg atk
VER=2.38.0
fetch "https://download.gnome.org/sources/atk/2.38/atk-$VER.tar.xz"
extract_auto "atk-$VER.tar.xz" atk
patch -d "$SRC/atk" -p1 -R --dry-run -f < "$PATCHES/atk/iface-init-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/atk" -p1 < "$PATCHES/atk/iface-init-signatures.patch"
me atk -Ddocs=false -Dintrospection=false
wasmtest atk atk_test.c $(pkg-config --static --cflags --libs atk) -lpthread
manifest atk "$VER"
touch "$STAMPS/atk.ok"
