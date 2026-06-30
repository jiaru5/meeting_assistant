#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! processing_output="$(./platform/e2e/smoke-test.sh)"; then
  printf '%s\n' "$processing_output"
  exit 1
fi
printf '%s\n' "$processing_output"
case "$processing_output" in
  *"p2-c processing local e2e smoke passed."*) ;;
  *) echo "processing local smoke success marker missing" >&2; exit 1 ;;
esac

if ! bridge_output="$(./platform/e2e/native-transcript-bridge-smoke.sh)"; then
  printf '%s\n' "$bridge_output"
  exit 1
fi
printf '%s\n' "$bridge_output"
case "$bridge_output" in
  *"processing-to-native transcript bridge e2e smoke passed."*) ;;
  *) echo "native bridge smoke success marker missing" >&2; exit 1 ;;
esac

echo "full-stack e2e smoke passed."
