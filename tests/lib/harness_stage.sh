#!/usr/bin/env bash
# tests/lib/harness_stage.sh — stage the built inkscape module + harness page
# into build/harness/. Source from tests/t6/run.sh (or t7) after common.sh.
set -euo pipefail

stage_harness() {
  local out="$BUILD/harness" daemon="$SRC/gtk3/gdk/broadway"
  mkdir -p "$out"
  cp "$BUILD/inkscape/bin/inkscape.js" "$BUILD/inkscape/bin/inkscape.data" \
     "$BUILD/inkscape/bin/inkscape.wasm" "$out/"
  cp "$ROOT/bridge/bridge.js" "$out/"
  cp "$daemon/rawinflate.min.js" "$out/"   # broadway.js decodes surfaces with it
  # broadway.js: swap the WebSocket for our in-memory BridgeSocket
  sed -e 's/ws = new WebSocket(loc, "broadway");/ws = new BridgeSocket();/' \
      "$daemon/broadway.js" > "$out/broadway.js"
  grep -q "new BridgeSocket()" "$out/broadway.js" # sed must have matched
  cp "$ROOT"/harness/index.html "$ROOT"/harness/loader.js "$out/"
  local ver
  ver="$(sha256sum "$out/inkscape.wasm" | cut -c1-12)"
  sed -i -E "s/(src=\"[^\"]+\\.(js))\"/\\1?v=$ver\"/g" "$out/index.html"
  sed -i -E "s/new URL\\(f, document\\.baseURI\\)\\.href/new URL(f + '?v=$ver', document.baseURI).href/" "$out/loader.js"
}
