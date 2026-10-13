#!/usr/bin/env bash
# tests/lib/wasm_harness.sh — build a broadway-bridge test module + harness
# page into build/<name>/. Source from tests/<name>/run.sh after common.sh.
set -euo pipefail

build_harness() { # build_harness <name> <src> [extra args...]
  local name="$1" src="$2"; shift 2
  local out="$BUILD/$name"
  local daemon="$SRC/gtk3/gdk/broadway"
  mkdir -p "$out"
  daemon_objs "$TEST/daemon"

  local comp=emcc; case "$src" in *.cpp|*.cc|*.mm) comp=em++;; esac

  "$comp" "$ROOT/$src" "$ROOT/bridge/bytepipe.c" "$ROOT/bridge/bridge.c" \
    "$TEST/daemon"/*.o \
    -o "$out/$name.js" \
    -O1 -g1 -ffunction-sections -fdata-sections -fexceptions -frtti \
    -I"$BUILD/gtk3" -I"$BUILD/gtk3/gdk/broadway" \
    -I"$SRC/gtk3/gdk" -I"$SRC/gtk3/gdk/broadway" \
    -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=0 -sMODULARIZE=1 -sEXPORT_NAME=Module \
    -sSTACK_SIZE=8388608 -sALLOW_TABLE_GROWTH=1 \
    -sEMULATE_FUNCTION_POINTER_CASTS=1 \
    -sEXPORTED_FUNCTIONS=_main,_malloc,_free,_bridge_frame,_bridge_js_connect,_bridge_js_write,_bridge_js_poll,_bridge_js_poll_ptr \
    --preload-file "$ROOT/tests/fixtures@/fixtures" \
    -I"$SYSROOT/include" -L"$SYSROOT/lib" "$@" "$SYSROOT/lib/libpthread.a"

  cp "$ROOT/bridge/bridge.js" "$out/"
  # broadway.js: swap the WebSocket for our in-memory BridgeSocket
  sed -e 's/ws = new WebSocket(loc, "broadway");/ws = new BridgeSocket();/' \
      "$daemon/broadway.js" > "$out/broadway.js"
  grep -q "new BridgeSocket()" "$out/broadway.js" # sed must have matched
}
