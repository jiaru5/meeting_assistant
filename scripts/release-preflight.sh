#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "release-preflight failed: $1" >&2
  exit 1
}

run_step() {
  local name="$1"
  shift
  echo
  echo "==> $*"
  ./scripts/evidence-run.sh release "$name" "$@"
}

rm -rf "${HARNESS_EVIDENCE_DIR:-.harness/evidence}/release"

run_step production-readiness ./scripts/production-readiness-check.sh

if grep -n -E '^\| OD-[^|]* \| open \|' docs/product-spec/10-open-decisions.md; then
  fail "open product or technical decisions remain"
fi

uncovered_rows="$(
  awk '/^\| PV-/ && $0 !~ /\| `covered` \|$/ && $0 !~ /PV-AREA-/ { print }' \
    docs/engineering/06-product-validation-matrix.md
)"

if [ -n "$uncovered_rows" ]; then
  printf '%s\n' "$uncovered_rows" >&2
  fail "validation matrix contains non-covered PV-* rows"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  generated_or_secret="$(
    {
      git ls-files
      git ls-files --others --exclude-standard
    } | sort -u | awk '
      /^\.DS_Store$/ ||
      (/^\.env($|\.)/ && $0 != ".env.example" && $0 != ".env.prod.example") ||
      /\.local$/ ||
      /\.log$/ ||
      /^frontend\/.*\/node_modules\// ||
      /^frontend\/.*\/dist\// ||
      /^frontend\/.*\/coverage\// ||
      /^frontend\/.*\/playwright-report\// ||
      /^frontend\/.*\/test-results\// ||
      /^backend\/.*\/target\// {
        print
      }
    '
  )"
  if [ -n "$generated_or_secret" ]; then
    printf '%s\n' "$generated_or_secret" >&2
    fail "generated, local, or secret-like files are tracked or pending"
  fi
fi

run_step docs ./scripts/docs-check.sh
run_step check ./scripts/check.sh
run_step mocked-e2e ./scripts/test-e2e.sh
run_step full-stack-e2e ./scripts/test-e2e-full-stack.sh
run_step supply-chain ./scripts/supply-chain-check.sh release
run_step review-report ./scripts/review-report.sh --require-release-evidence

echo
echo "release-preflight passed."
