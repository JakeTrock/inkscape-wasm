#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/wasm_harness.sh

[ -f "$BUILD/stamps/check-2.ok" ] && { echo "check-2 cached"; exit 0; }

build_harness t2 tests/t2/hello.c $(pkg-config --static --cflags --libs gtk+-3.0)

# playwright deps (browsers already cached; never download here)
if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t2/t2.spec.ts --reporter=line )

mkdir -p "$BUILD/stamps"
touch "$BUILD/stamps/check-2.ok"
echo "PASS: check-2"
