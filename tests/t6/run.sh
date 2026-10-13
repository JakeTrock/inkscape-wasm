#!/usr/bin/env bash
# T6 gate: full inkscape GUI boots in the harness page (browser, Playwright).
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/harness_stage.sh

[ -f "$STAMPS/check-6.ok" ] && { echo "check-6 cached"; exit 0; }

[ -f "$BUILD/inkscape/bin/inkscape.js" ] || { echo "no inkscape module — run: make pkg-inkscape"; exit 1; }

mkdir -p "$BUILD/t6"
stage_harness

if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t6/t6.spec.ts --reporter=line )

mkdir -p "$STAMPS"
touch "$STAMPS/check-6.ok"
echo "PASS: check-6"
