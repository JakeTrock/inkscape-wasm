#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/wasm_harness.sh

[ -f "$BUILD/stamps/check-3.ok" ] && { echo "check-3 cached"; exit 0; }

build_harness t3 tests/t3/hello.cpp $(pkg-config --static --cflags --libs gtkmm-3.0)

# playwright deps (browsers already cached; never download here)
if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t3/t3.spec.ts --reporter=line )

mkdir -p "$BUILD/stamps"
touch "$BUILD/stamps/check-3.ok"
echo "PASS: check-3"
