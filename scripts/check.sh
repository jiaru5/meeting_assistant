#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

evidence_root="${HARNESS_EVIDENCE_DIR:-.harness/evidence}"
rm -rf "$evidence_root/check"

run_step() {
  local name="$1"
  shift
  ./scripts/evidence-run.sh check "$name" "$@"
}

run_step docs-check ./scripts/docs-check.sh
run_step adoption ./scripts/adoption-check.sh
run_step manifest ./scripts/project-manifest-check.sh current
run_step harness-self-test ./scripts/harness-self-test.sh
run_step compose ./scripts/compose-check.sh
run_step workflow ./scripts/agent-workflow-check.sh
run_step prod-config ./scripts/prod-config-check.sh
run_step architecture ./scripts/architecture-check.sh
run_step security ./scripts/security-check.sh
run_step supply-chain ./scripts/supply-chain-check.sh current
run_step migration ./scripts/db-migration-check.sh
run_step lint ./scripts/lint.sh
run_step test ./scripts/test.sh
run_step build ./scripts/build.sh

echo "check passed with evidence under $evidence_root/check."
