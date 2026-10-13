#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.." ; source packages/common.sh
begin_pkg glib
VER=2.88.0
fetch "https://download.gnome.org/sources/glib/2.88/glib-$VER.tar.xz"
extract_auto "glib-$VER.tar.xz" glib
grep -q "!= 'emscripten'" "$SRC/glib/gio/meson.build" \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/no-resolv-emscripten.patch"
grep -q "musl's size_t" "$SRC/glib/meson.build" \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/wasm32-gsize-long.patch"
grep -q "not posix_spawnp" "$SRC/glib/meson.build" \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/no-posix-spawn-emscripten.patch"
grep -q "libpthread supplement" "$SRC/glib/meson.build" \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/no-threads-emscripten.patch"
grep -q "__EMSCRIPTEN__" "$SRC/glib/glib/glib-unix.c" \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/unix-fd-query-path-emscripten.patch"
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/no-tool-install-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/no-tool-install-emscripten.patch"
# wasm strict function types: G_DEFINE_* macros register 1-arg functions as
# 2-arg callbacks. Every GObject consumer compiles against this header.
# (g_object_do_class_init is covered by iface-init-signatures.patch)
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gtype-h-wasm-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gtype-h-wasm-signatures.patch"
# wasm: app objects' static ctors (GType registrations) precede archives in
# link order — gobject's unprioritized ctor loses the race; prioritize it
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gobject-ctor-priority.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gobject-ctor-priority.patch"
# wasm: thread-pool workers can't exist; run pushed jobs inline (GTask async
# module loading etc. would otherwise wait forever for a worker)
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gthreadpool-inline-push.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gthreadpool-inline-push.patch"
# hand-written param spec registrations: 22 1-arg instance_init functions
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gparamspecs-instance-init-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gparamspecs-instance-init-signatures.patch"
# ...and the GParamSpecTypeInfo field that lies about being 1-arg
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gparam-h-instance-init-type.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gparam-h-instance-init-type.patch"
# wasm: marshals must call class-closure members without the trailing user_data
patch -d "$SRC/glib" -p1 -R --dry-run -f < "$PATCHES/glib/gmarshal-class-callbacks.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "$PATCHES/glib/gmarshal-class-callbacks.patch"
patch -d "$SRC/glib" -p1 -R --dry-run -f < "patches/glib/iface-init-signatures.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/glib" -p1 < "patches/glib/iface-init-signatures.patch"
# Libraries only: glib's internal executables (gtester, gio-querymodules...)
# fail to link on emscripten (meson injects -pthread; posix_spawn missing).
meson setup "$BUILD/glib" "$SRC/glib" --prefix="$SYSROOT" \
  --cross-file "$BUILD/emsdk.cross" --buildtype=release \
  --default-library=static \
  -Dtests=false -Ddocumentation=false -Dintrospection=disabled \
  -Dlibmount=disabled -Dlibelf=disabled -Dselinux=disabled -Dxattr=false \
  -Dnls=disabled -Dglib_debug=disabled -Doss_fuzz=disabled \
  -Dman-pages=disabled
ninja -C "$BUILD/glib" -j 64 \
  glib/libglib-2.0.a gobject/libgobject-2.0.a gio/libgio-2.0.a \
  gmodule/libgmodule-2.0.a gthread/libgthread-2.0.a \
  girepository/gi-visibility.h girepository/libgirepository-2.0.a
meson install -C "$BUILD/glib" --no-rebuild
# Cross builds: host tools, not sysroot tools (we install none on emscripten)
for t in gio gio-querymodules glib-compile-schemas glib-compile-resources gdbus gdbus-codegen gresource gsettings; do
  sed -i "s|^\\([a-z_]*\\)=.*${t}\$|\\1=/usr/bin/${t}|" "$SYSROOT/lib/pkgconfig/gio-2.0.pc"
done
sed -i 's|^gio=.*|gio=/usr/bin/gio|' "$SYSROOT/lib/pkgconfig/gio-2.0.pc"
wasmtest glib glib_test.c $(pkg-config --static --cflags --libs gobject-2.0) -lpthread
manifest glib "$VER"
touch "$STAMPS/glib.ok"
