#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "security-check failed: $1" >&2
  exit 1
}

./scripts/project-manifest-check.sh current
python3 scripts/action-pin-check.py
./scripts/prod-config-check.sh

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git grep -I -n -E \
    '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{30,}' \
    -- . \
    ':(exclude)example-smart_team-harness_engineering/**' \
    ':(exclude)scripts/security-check.sh' 2>/dev/null; then
    fail "high-confidence credential material detected in tracked files"
  fi
fi

python3 scripts/harness-runtime.py run-gate security

echo "security-check passed."
