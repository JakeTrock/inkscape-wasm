#!/usr/bin/env bash
# T5 gate: inkscape.wasm headless SVG->PNG export in node, golden-compared.
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh

[ -f "$STAMPS/check-5.ok" ] && { echo "check-5 cached"; exit 0; }

INK="$BUILD/inkscape/bin/inkscape.js"
[ -f "$INK" ] || { echo "no inkscape.wasm — run: make pkg-inkscape"; exit 1; }
[ -x "$BUILD/native/inkscape/bin/inkscape" ] || { echo "no native inkscape — run: make native-inkscape"; exit 1; }

mkdir -p "$BUILD/t5"
fail=0
for f in basic text gradients transforms clip-mask; do
  echo "== $f =="
  ( GDK_BACKEND=unsupported node tests/t5/driver.mjs "$INK" "/fixtures/$f.svg" "$BUILD/t5/$f.png" ) \
    || { echo "FAIL: $f export (see above)"; fail=1; continue; }
  max=$(node -p "require('./tests/manifest')['$f']")
  ( node tests/t5/compare.mjs "$BUILD/t5/$f.png" "tests/golden/$f.png" "$max" ) \
    || { echo "FAIL: $f compare"; fail=1; }
done

[ "$fail" = 0 ] || exit 1
mkdir -p "$STAMPS"
touch "$STAMPS/check-5.ok"
echo "PASS: check-5"
