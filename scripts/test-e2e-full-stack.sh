#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export MEETING_ASSISTANT_SMOKE_IMAGE="${MEETING_ASSISTANT_SMOKE_IMAGE:-meeting-assistant-smoke:local}"

python3 scripts/harness-runtime.py full-stack-e2e

echo "test-e2e-full-stack passed."
