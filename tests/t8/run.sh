#!/usr/bin/env bash
# T8 gate: icons rendered, zero console CRITICAL/WARNING/pageerror, non-occluded
# canvas, and Save on a fresh canvas without prior Open.
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/harness_stage.sh

[ -f "$STAMPS/check-8.ok" ] && { echo "check-8 cached"; exit 0; }

[ -f "$BUILD/inkscape/bin/inkscape.js" ] || { echo "no inkscape module — run: make pkg-inkscape"; exit 1; }

mkdir -p "$BUILD/t8"
stage_harness

if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t8/t8.spec.ts --reporter=line )

mkdir -p "$STAMPS"
touch "$STAMPS/check-8.ok"
echo "PASS: check-8"
