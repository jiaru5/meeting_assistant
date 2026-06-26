#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f ".env" ]; then
  echo "No .env found. For local development, copy .env.example to .env and adjust ports or credentials."
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Docker is required for integrated dependencies and deployment verification."
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. Python 3 is required for manifest validation and harness self-tests." >&2
  exit 1
fi

./scripts/docs-check.sh
./scripts/adoption-check.sh
./scripts/project-manifest-check.sh current
./scripts/harness-self-test.sh
./scripts/agent-workflow-check.sh

echo "bootstrap passed."
