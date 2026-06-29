#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

./platform/e2e/smoke-test.sh
./platform/e2e/native-transcript-bridge-smoke.sh

echo "full-stack e2e smoke passed."
