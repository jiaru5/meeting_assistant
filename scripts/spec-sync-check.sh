#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=()
high_risk_files=()

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

if [ "${#CHANGED_FILES[@]}" -eq 0 ]; then
  echo "spec-sync-check passed: no local or PR diff changes detected."
  exit 0
fi

product_surface_changed=false
product_spec_changed=false
validation_matrix_changed=false
contract_level_changed=false

mark_contract_level_change() {
  contract_level_changed=true
  high_risk_files+=("$1")
}

for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
  case "$file" in
    example-smart_team-harness_engineering/*)
      ;;
    docs/product-spec/*)
      product_surface_changed=true
      product_spec_changed=true
      ;;
    docs/engineering/06-product-validation-matrix.md)
      validation_matrix_changed=true
      ;;
    backend/services/*/src/main/resources/db/migration/*|backend/contracts/*)
      product_surface_changed=true
      mark_contract_level_change "$file"
      ;;
    backend/services/*/src/main/java/*/api/*|backend/services/*/src/main/java/*/domain/*)
      product_surface_changed=true
      mark_contract_level_change "$file"
      ;;
    backend/services/*/src/main/java/*/application/*Command.java|backend/services/*/src/main/java/*/application/*Request.java|backend/services/*/src/main/java/*/application/*Response.java|backend/services/*/src/main/java/*/application/*View.java)
      product_surface_changed=true
      mark_contract_level_change "$file"
      ;;
    backend/services/*/src/main/*)
      product_surface_changed=true
      ;;
    frontend/apps/*/src/routes.tsx|frontend/apps/*/src/shared/api/*|frontend/packages/api-client/*)
      product_surface_changed=true
      mark_contract_level_change "$file"
      ;;
    frontend/apps/*/src/*|frontend/apps/*/tests/e2e/*|frontend/packages/ui/src/*)
      product_surface_changed=true
      ;;
  esac
done

if [ "$product_surface_changed" = false ]; then
  echo "spec-sync-check passed: no product surface changes detected."
  exit 0
fi

if [ "$validation_matrix_changed" = false ]; then
  add_failure "Product surface changes require docs/engineering/06-product-validation-matrix.md to be reviewed and updated."
fi

if [ "$contract_level_changed" = true ] && [ "$product_spec_changed" = false ]; then
  add_failure "Contract-level product changes require a docs/product-spec/* update before implementation is considered complete."
fi

if [ "${#failures[@]}" -gt 0 ]; then
  echo "spec-sync-check failed:" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  echo >&2
  echo "Spec sync classification required for product work:" >&2
  echo " - spec-change: update the owning docs/product-spec/* chapter first, then code, tests, and validation matrix." >&2
  echo " - spec-covered: keep product spec unchanged only when the diff implements existing spec behavior and updates validation evidence." >&2
  echo " - no-product-impact: split pure refactors or engineering-only work away from product surface changes when possible." >&2

  if [ "${#high_risk_files[@]}" -gt 0 ]; then
    echo >&2
    echo "Contract-level files considered by this gate:" >&2
    printf ' - %s\n' "${high_risk_files[@]}" >&2
  fi

  echo >&2
  echo "Changed files considered by the gate:" >&2
  printf ' - %s\n' "${CHANGED_FILES[@]}" >&2
  exit 1
fi

echo "spec-sync-check passed."
