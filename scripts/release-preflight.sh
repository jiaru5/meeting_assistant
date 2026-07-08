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

release_distribution_mode="${MEETING_ASSISTANT_RELEASE_DISTRIBUTION_MODE:-local-direct}"
case "$release_distribution_mode" in
  local-direct|developer-id)
    ;;
  *)
    fail "MEETING_ASSISTANT_RELEASE_DISTRIBUTION_MODE must be local-direct or developer-id"
    ;;
esac

default_source_repository="$(git config --get remote.origin.url 2>/dev/null || true)"
default_source_repository="${default_source_repository:-local/meeting_assistant}"
release_source_repository="${MEETING_ASSISTANT_RELEASE_SOURCE_REPOSITORY:-$default_source_repository}"
release_builder="${MEETING_ASSISTANT_RELEASE_BUILDER:-release-preflight-$release_distribution_mode}"
local_direct_app_path="${MEETING_ASSISTANT_LOCAL_DIRECT_APP_PATH:-${MA_NATIVE_LOCAL_APP_INSTALL_PATH:-$HOME/Applications/MeetingAssistantNativeLocal.app}}"

run_local_direct_release_candidate_gates() {
  run_step release-candidate-inputs \
    ./scripts/release-candidate-inputs.py \
    --distribution-mode local-direct \
    --builder "$release_builder" \
    --source-repository "$release_source_repository"

  run_step local-direct-install \
    ./platform/native-app/scripts/install-local-app.sh \
    --no-build \
    --install-path "$local_direct_app_path"

  run_step local-direct-functional \
    env MA_LOCAL_DIRECT_FUNCTIONAL_BUILD_SOURCE=0 \
    ./platform/e2e/local-direct-functional-preflight.sh \
    --no-build \
    --app "$local_direct_app_path"

  run_step product-validation-local-functional \
    ./scripts/product-validation-check.py local-functional
}

run_release_scope_native_capture_gates() {
  run_step native-capture ./platform/e2e/release-native-capture-artifact-smoke.sh
  run_step real-capture-same-chain ./platform/e2e/release-real-capture-same-chain-smoke.sh
  run_step native-ui-hardening ./platform/e2e/release-native-ui-hardening-smoke.sh
}

rm -rf "${HARNESS_EVIDENCE_DIR:-.harness/evidence}/release"

run_step production-readiness ./scripts/production-readiness-check.sh

if grep -n -E '^\| OD-[^|]* \| open \|' docs/product-spec/10-open-decisions.md; then
  fail "open product or technical decisions remain"
fi

python3 scripts/vs-stage-check.py release || fail "VS-MA release prerequisites are not closed"
python3 scripts/product-validation-check.py release || fail "validation matrix contains non-covered release-scope PV-* rows"

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
if [ "$release_distribution_mode" = "local-direct" ]; then
  run_local_direct_release_candidate_gates
else
  run_release_scope_native_capture_gates
fi
run_step provider-hardening ./platform/e2e/release-capture-processing-hardening-smoke.sh
run_step security-supply-chain ./platform/e2e/release-security-supply-chain-smoke.sh
run_step full-stack-e2e ./scripts/test-e2e-full-stack.sh
run_step release-bundle ./scripts/release-bundle-check.sh
run_step supply-chain ./scripts/supply-chain-check.sh release
run_step review-report ./scripts/review-report.sh --require-release-evidence

echo
echo "release-preflight passed."
