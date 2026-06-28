#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=()

add_failure() {
  failures+=("$1")
}

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

is_zero_sha() {
  [[ "$1" =~ ^0+$ ]]
}

changed_files() {
  if ! is_git_repo; then
    return 0
  fi

  local base_ref="${AGENT_BASE_REF:-}"
  if [ -n "$base_ref" ] && ! is_zero_sha "$base_ref" && git cat-file -e "$base_ref^{commit}" 2>/dev/null; then
    git diff --name-only --diff-filter=ACMRT "$base_ref"...HEAD
    return
  fi

  {
    git diff --name-only --diff-filter=ACMRT
    git diff --cached --name-only --diff-filter=ACMRT
    git ls-files --others --exclude-standard
  } | sort -u
}

CHANGED_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] && CHANGED_FILES+=("$file")
done < <(changed_files)

has_changed_file() {
  local candidate="$1" file
  for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    [ "$file" = "$candidate" ] && return 0
  done
  return 1
}

has_match() {
  local pattern="$1" file
  for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    case "$file" in
      example-smart_team-harness_engineering/*) ;;
      $pattern) return 0 ;;
    esac
  done
  return 1
}

has_product_behavior_change() {
  local file
  for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    case "$file" in
      example-smart_team-harness_engineering/*|docs/product-spec/PROJECT-STATUS.md)
        ;;
      docs/product-spec/*|backend/services/*/src/main/*|backend/contracts/*|frontend/apps/*/src/*|frontend/apps/*/tests/e2e/*|frontend/packages/api-client/*|frontend/packages/ui/src/*|platform/native-app/component.json|platform/processing-cli/component.json|platform/native-app/Sources/*|platform/native-app/Tests/*|platform/native-app/UITests/*|platform/processing-cli/src/*|platform/processing-cli/tests/*|platform/e2e/*)
        return 0
        ;;
    esac
  done
  return 1
}

has_engineering_workflow_change() {
  local file
  for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    case "$file" in
      example-smart_team-harness_engineering/*|harness/adoption-state.json)
        ;;
      scripts/*|harness/*|.github/workflows/*|docker-compose*.yml|platform/infra/*|docs/adoption/*|docs/engineering/*)
        return 0
        ;;
    esac
  done
  return 1
}

require_executable() {
  local file="$1"
  if [ ! -x "$file" ]; then
    add_failure "$file must exist and be executable."
  fi
}

require_executable "scripts/agent-workflow-check.sh"
require_executable "scripts/activate-project.sh"
require_executable "scripts/adoption-check.sh"
require_executable "scripts/adoption-runtime.py"
require_executable "scripts/adoption-status.sh"
require_executable "scripts/architecture-check.sh"
require_executable "scripts/compose-check.sh"
require_executable "scripts/harness-self-test.sh"
require_executable "scripts/project-manifest-check.sh"
require_executable "scripts/prod-config-check.sh"
require_executable "scripts/product-validation-check.py"
require_executable "scripts/production-readiness-check.sh"
require_executable "scripts/phase-preflight.sh"
require_executable "scripts/release-preflight.sh"
require_executable "scripts/review-report.sh"
require_executable "scripts/security-check.sh"
require_executable "scripts/spec-sync-check.sh"
require_executable "scripts/start-project.sh"
require_executable "scripts/supply-chain-check.sh"

if [ "${#CHANGED_FILES[@]}" -eq 0 ]; then
  ./scripts/spec-sync-check.sh >/dev/null
  ./scripts/review-report.sh --check >/dev/null
  echo "agent-workflow-check passed: no local or PR diff changes detected."
  exit 0
fi

product_behavior_changed=false
if has_product_behavior_change; then
  product_behavior_changed=true
fi

implementation_changed=false
if has_match "backend/services/*/src/main/*" \
  || has_match "frontend/apps/*/src/*" \
  || has_match "frontend/packages/*/src/*" \
  || has_match "platform/native-app/Sources/*" \
  || has_match "platform/processing-cli/src/*" \
  || has_match "backend/services/*/Dockerfile" \
  || has_match "frontend/apps/*/Dockerfile" \
  || has_match "docker-compose*.yml"; then
  implementation_changed=true
fi

test_changed=false
if has_match "backend/services/*/src/test/*" \
  || has_match "frontend/apps/*/src/*.test.*" \
  || has_match "frontend/apps/*/tests/e2e/*" \
  || has_match "platform/native-app/Tests/*" \
  || has_match "platform/native-app/UITests/*" \
  || has_match "platform/native-app/tests/*" \
  || has_match "platform/processing-cli/tests/*" \
  || has_match "platform/e2e/*" \
  || has_match "scripts/test*.sh" \
  || has_match "scripts/db-migration-check.sh"; then
  test_changed=true
fi

engineering_changed=false
if has_engineering_workflow_change; then
  engineering_changed=true
fi

if [ "$implementation_changed" = true ] && [ "$test_changed" = false ]; then
  add_failure "Implementation changes require corresponding backend, frontend, platform, E2E, or test script changes."
fi

if [ "$product_behavior_changed" = true ] && ! has_changed_file "docs/engineering/06-product-validation-matrix.md"; then
  add_failure "Product/spec/behavior changes require docs/engineering/06-product-validation-matrix.md to be reviewed and updated."
fi

if [ "$engineering_changed" = true ] && ! has_match "docs/engineering/*"; then
  add_failure "Engineering workflow, Docker, CI, or script changes require a docs/engineering/* update."
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts -maxdepth 1 -type f -name "*.sh" | sort)

./scripts/spec-sync-check.sh >/dev/null
./scripts/adoption-check.sh >/dev/null
./scripts/project-manifest-check.sh current >/dev/null
./scripts/review-report.sh --check >/dev/null

if [ "${#failures[@]}" -gt 0 ]; then
  echo "agent-workflow-check failed:" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  echo >&2
  echo "Changed files considered by the gate:" >&2
  printf ' - %s\n' "${CHANGED_FILES[@]}" >&2
  exit 1
fi

echo "agent-workflow-check passed."
