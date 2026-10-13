#!/usr/bin/env bash
# T7 gate: scripted GUI session — draw rect, save, export; exported PNG
# pixel-compared against a native export of the SAME saved document.
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/harness_stage.sh

[ -f "$STAMPS/check-7.ok" ] && { echo "check-7 cached"; exit 0; }

[ -f "$BUILD/inkscape/bin/inkscape.js" ] || { echo "no inkscape module — run: make pkg-inkscape"; exit 1; }
BIN="$BUILD/native/inkscape/bin/inkscape"
[ -x "$BIN" ] || { echo "no native inkscape — run: make native-inkscape"; exit 1; }

mkdir -p "$BUILD/t7"
stage_harness

if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t7/t7.spec.ts --reporter=line )

# native golden of the document this run produced (self-consistent compare)
PROFILE="$BUILD/native-profile"
mkdir -p "$PROFILE"
cp "$ROOT/tests/fixtures/inkscape-prefs.xml" "$PROFILE/preferences.xml"
export INKSCAPE_PROFILE_DIR="$PROFILE"
"$BIN" --batch-process --actions \
  "file-open:$PWD/build/t7/t7-saved.svg; export-filename:$PWD/build/t7/t7-native.png; export-do; file-close" \
  >"$LOGS/t7-native.log" 2>&1 || { echo "FAIL: native export (log: build/logs/t7-native.log)"; exit 1; }

node tests/t5/compare.mjs "$BUILD/t7/t7-wasm.png" "$BUILD/t7/t7-native.png" \
  "$(node -p "require('./tests/manifest')['t7']")"

mkdir -p "$STAMPS"
touch "$STAMPS/check-7.ok"
echo "PASS: check-7"
