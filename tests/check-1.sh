#!/usr/bin/env bash
# T1 gate: every Leg-A package built+stamped, every consumer pkg-config module
# resolvable in the sysroot. (potrace was cut — see findings.md.)
set -euo pipefail
cd "$(dirname "$0")/.." ; source packages/common.sh
fail=0
PKGS="zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
      libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
      atkmm gtkmm libxml2 libxslt gsl dconv lcms2 boost libgc potrace lib2geom"
for p in $PKGS; do
  [ -e "$STAMPS/$p.ok" ] || { echo "MISSING STAMP: $p"; fail=1; }
done
for m in zlib libpng freetype2 fontconfig pixman-1 fribidi harfbuzz cairo ffi \
         glib-2.0 gobject-2.0 gio-2.0 pango pangocairo gdk-pixbuf-2.0 atk \
         gtk+-3.0 sigc++-2.0 glibmm-2.4 cairomm-1.0 pangomm-1.4 atkmm-1.6 \
         gtkmm-3.0 libxml-2.0 libxslt gsl double-conversion gc lcms2 2geom; do
  pkg-config --modversion "$m" >/dev/null 2>&1 \
    || { echo "PKG-CONFIG MISSING: $m"; fail=1; }
done
[ -f "$SYSROOT/include/boost/optional.hpp" ] || { echo "MISSING: boost headers"; fail=1; }
[ -f "$SYSROOT/lib/libboost_filesystem.a" ] || { echo "MISSING: libboost_filesystem"; fail=1; }
[ -f "$SYSROOT/include/potracelib.h" ] || { echo "MISSING: potrace headers"; fail=1; }
if [ "$fail" = 0 ]; then echo "check-1 PASS ($(grep -c . build/manifest.txt) packages in manifest)"; else exit 1; fi
