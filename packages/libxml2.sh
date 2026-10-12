#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg libxml2
VER=2.13.6
fetch "https://download.gnome.org/sources/libxml2/2.13/libxml2-$VER.tar.xz"
extract_auto "libxml2-$VER.tar.xz" libxml2
me libxml2 -Dhistory=false -Dhttp=false -Dftp=false -Dreadline=false -Diconv=enabled \
  -Dicu=disabled -Dlzma=disabled -Dpython=false \
  -Dzlib=enabled -Dlegacy=true
# threads stay enabled (default): libxslt expects the __xml*-globals ABI;
# pthread symbols come from our supplement.
# upstream .pc bug: Cflags lacks the libxml2/ include subdir; also strip
# meson's injected -pthread (consumers must stay non-mt)
sed -i 's|^Cflags: -I\${includedir}.*|Cflags: -I${includedir}/libxml2|' "$SYSROOT/lib/pkgconfig/libxml-2.0.pc"
# meson builds install no xml2-config; libxslt's configure prefers one over
# pkg-config and would pick the host's (2.15) — version-skewing the build.
cat > "$SYSROOT/bin/xml2-config" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo 2.13.6 ;;
  --cflags) echo -I/home/jake/reversing/inkscape/build/sysroot/include/libxml2 ;;
  --libs) echo -L/home/jake/reversing/inkscape/build/sysroot/lib -lxml2 -lz -lm -lpthread ;;
  *) echo "" ;;
esac
EOF
chmod +x "$SYSROOT/bin/xml2-config"
wasmtest libxml2 libxml2_test.c $(pkg-config --cflags --libs libxml-2.0) -lpthread
manifest libxml2 "$VER"
touch "$STAMPS/libxml2.ok"
