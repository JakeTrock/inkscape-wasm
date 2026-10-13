#!/usr/bin/env bash
# Generate golden PNGs from the native Inkscape build (same 1.4.4 source).
# Regenerating needs a stated reason in the commit message (spec rule).
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh

BIN="$BUILD/native/inkscape/bin/inkscape"
[ -x "$BIN" ] || { echo "no native inkscape — run: make native-inkscape"; exit 1; }

# same clean profile as the wasm side (no welcome screen / splash blocking)
PROFILE="$BUILD/native-profile"
mkdir -p "$PROFILE"
cp "$ROOT/tests/fixtures/inkscape-prefs.xml" "$PROFILE/preferences.xml"
export INKSCAPE_PROFILE_DIR="$PROFILE"

mkdir -p tests/golden
for f in basic text gradients transforms clip-mask; do
  "$BIN" --batch-process --actions \
    "file-open:$ROOT/tests/fixtures/$f.svg; export-filename:$ROOT/tests/golden/$f.png; export-do; file-close" \
    >"$LOGS/golden-$f.log" 2>&1 || { echo "FAIL: $f (log: build/logs/golden-$f.log)"; exit 1; }
  echo "golden: $f.png ($(stat -c%s tests/golden/$f.png) bytes)"
done
echo "goldens regenerated — commit with a stated reason"
