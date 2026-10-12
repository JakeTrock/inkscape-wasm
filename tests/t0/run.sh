#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."; source packages/common.sh
wasmtest t0 t0_smoke.cpp
