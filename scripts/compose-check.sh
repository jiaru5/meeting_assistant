#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "compose-check failed: docker is required." >&2
  exit 1
fi

docker compose -f docker-compose.yml -f docker-compose.test.yml config --quiet

echo "compose-check passed."
