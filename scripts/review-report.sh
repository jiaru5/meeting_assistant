#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

product_surface_changed() {
  has_match "docs/product-spec/*" \
    || has_match "backend/services/*/src/main/*" \
    || has_match "backend/contracts/*" \
    || has_match "frontend/apps/*/src/*" \
    || has_match "frontend/apps/*/tests/e2e/*" \
    || has_match "platform/native-app/component.json" \
    || has_match "platform/processing-cli/component.json" \
    || has_match "platform/native-app/Sources/*" \
    || has_match "platform/native-app/Tests/*" \
    || has_match "platform/native-app/UITests/*" \
    || has_match "platform/processing-cli/src/*" \
    || has_match "platform/processing-cli/tests/*" \
    || has_match "platform/e2e/*"
}

project_mode() {
  awk -F: '
    /^[[:space:]]*mode[[:space:]]*:/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' docs/product-spec/PROJECT-STATUS.md
}

print_changed_subset() {
  local pattern="$1" file found=false
  if [ "${#CHANGED_FILES[@]}" -eq 0 ]; then
    printf -- '- None detected.\n'
    return
  fi
  for file in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    case "$file" in
      example-smart_team-harness_engineering/*)
        ;;
      $pattern)
        printf -- '- `%s`\n' "$file"
        found=true
        ;;
    esac
  done
  if [ "$found" = false ]; then
    printf -- '- None detected.\n'
  fi
}

recommended_validation() {
  echo '- `./scripts/docs-check.sh`'
  echo '- `./scripts/spec-sync-check.sh`'
  if has_match "docs/adoption/*" \
    || has_match "harness/adoption-state.json" \
    || has_match "scripts/adoption-*" \
    || has_match "scripts/start-project.sh" \
    || has_match "scripts/activate-project.sh"; then
    echo '- `./scripts/adoption-check.sh`'
  fi
  echo '- `./scripts/agent-workflow-check.sh`'
  echo '- `./scripts/prod-config-check.sh`'
  echo '- `./scripts/check.sh`'

  if has_match "backend/services/*/src/main/resources/db/migration/*" \
    || has_match "docker-compose*.yml" \
    || has_match "scripts/db-migration-check.sh"; then
    echo '- `./scripts/db-migration-check.sh`'
  fi

  if has_match "frontend/apps/*/src/*" \
    || has_match "frontend/apps/*/tests/e2e/*"; then
    echo '- `./scripts/test-e2e.sh`'
  fi

  if has_match "backend/services/*/src/main/*" \
    || has_match "frontend/apps/*/src/*" \
    || has_match "platform/native-app/Sources/*" \
    || has_match "platform/native-app/Tests/*" \
    || has_match "platform/native-app/UITests/*" \
    || has_match "platform/processing-cli/src/*" \
    || has_match "platform/processing-cli/tests/*" \
    || has_match "platform/e2e/*" \
    || has_match "docker-compose*.yml"; then
    echo '- `./scripts/test-e2e-full-stack.sh`'
  fi

  if has_match "platform/native-app/*" \
    || has_match "platform/processing-cli/*" \
    || has_match "platform/e2e/*"; then
    echo '- `./scripts/architecture-check.sh`'
    echo '- `./scripts/security-check.sh`'
    echo '- `./scripts/supply-chain-check.sh current`'
  fi
}

generate_report() {
  cat <<'REPORT'
# Agent Review Report

## Spec Alignment

- Product facts must come from `docs/product-spec/`.
- Engineering workflow facts must come from `docs/engineering/`.
- `AGENTS.md` is only the agent entrypoint and navigation protocol.

Changed product/spec files:
REPORT
  print_changed_subset "docs/product-spec/*"

  cat <<'REPORT'

Spec sync classification:
REPORT
  if ! product_surface_changed; then
    echo '- `no-product-impact`: no product surface changes detected in this diff.'
  elif [ "$(project_mode)" != "project" ] && has_match "docs/product-spec/*"; then
    echo '- `no-product-impact`: framework/adoption templates changed; no project product facts exist yet.'
  elif has_match "docs/product-spec/*"; then
    echo '- `spec-change`: product spec files changed; confirm owning chapters, validation matrix, tests and implementation are aligned.'
  else
    echo '- Product surface changed without product spec files. Treat this as `spec-covered` only if the diff implements existing facts and updates validation evidence.'
  fi

  cat <<'REPORT'

Changed engineering files:
REPORT
  print_changed_subset "docs/engineering/*"

  cat <<'REPORT'

Changed adoption workspace files:
REPORT
  print_changed_subset "docs/adoption/*"

  cat <<'REPORT'

Validation matrix status:
REPORT
  if has_match "docs/engineering/06-product-validation-matrix.md"; then
    echo '- `docs/engineering/06-product-validation-matrix.md` changed in this diff.'
  else
    echo '- No validation matrix change detected. Confirm this is correct before delivery.'
  fi

  cat <<'REPORT'

## Changed Surface

Backend:
REPORT
  print_changed_subset "backend/*"

  cat <<'REPORT'

Frontend:
REPORT
  print_changed_subset "frontend/*"

  cat <<'REPORT'

Platform, scripts, Docker and CI:
REPORT
  print_changed_subset "platform/*"
  print_changed_subset "harness/*"
  print_changed_subset "scripts/*"
  print_changed_subset "docker-compose*.yml"
  print_changed_subset ".github/workflows/*"

  cat <<'REPORT'

## Permission And Data Isolation

REPORT
  if has_match "docs/product-spec/03-permissions-and-identity.md" \
    || has_match "docs/product-spec/06-api-contracts.md" \
    || has_match "backend/services/*/src/main/java/*/api/*" \
    || has_match "backend/services/*/src/main/java/*/application/*" \
    || has_match "backend/services/*/src/main/java/*/security/*" \
    || has_match "platform/native-app/Sources/*" \
    || has_match "platform/native-app/Tests/*" \
    || has_match "platform/native-app/UITests/*" \
    || has_match "platform/processing-cli/src/*" \
    || has_match "platform/processing-cli/tests/*"; then
    echo "- Potentially impacted. Review tenant/workspace scope, current identity, service-side or local permission checks, service-to-service identity and audit."
  else
    echo "- No direct permission or data isolation surface detected in changed files."
  fi

  cat <<'REPORT'

## Test Evidence

Recommended commands for this diff:
REPORT
  recommended_validation

  cat <<'REPORT'

Recorded validation evidence:
REPORT
  evidence_found=false
  while IFS= read -r meta_file; do
    evidence_found=true
    step="$(awk -F= '$1 == "step" { print substr($0, index($0, "=") + 1) }' "$meta_file")"
    exit_code="$(awk -F= '$1 == "exit_code" { print $2 }' "$meta_file")"
    fingerprint="$(awk -F= '$1 == "worktree_fingerprint" { print $2 }' "$meta_file")"
    command="$(awk -F= '$1 == "command" { print substr($0, index($0, "=") + 1) }' "$meta_file")"
    log="$(awk -F= '$1 == "log" { print substr($0, index($0, "=") + 1) }' "$meta_file")"
    printf -- '- `%s`: exit `%s`; state `%s`; command `%s`; log `%s`\n' \
      "$step" "$exit_code" "$fingerprint" "$command" "$log"
  done < <(find "${HARNESS_EVIDENCE_DIR:-.harness/evidence}" -type f -name "*.meta" 2>/dev/null | sort)
  if [ "$evidence_found" = false ]; then
    echo "- No recorded evidence found. Run \`./scripts/check.sh\` before delivery."
  fi

  cat <<'REPORT'

Do not treat this generated report as a product fact source.

## Residual Risk

- Check `docs/engineering/06-product-validation-matrix.md` for remaining `partial`, `planned`, `missing` or `manual-evidence` rows in the changed scope.
- If this change introduced a new product or architecture decision, update `docs/product-spec/11-adr.md` before implementation is considered complete.
REPORT
}

if [ "${1:-}" = "--check" ] || [ "${1:-}" = "--require-evidence" ] || [ "${1:-}" = "--require-release-evidence" ]; then
  report="$(generate_report)"
  for section in "Spec Alignment" "Changed Surface" "Permission And Data Isolation" "Test Evidence" "Residual Risk"; do
    if ! grep -q "## $section" <<<"$report"; then
      echo "review-report check failed: missing section $section" >&2
      exit 1
    fi
  done
  if [ "${1:-}" = "--require-evidence" ] || [ "${1:-}" = "--require-release-evidence" ]; then
    evidence_dir="${HARNESS_EVIDENCE_DIR:-.harness/evidence}"
    evidence_scope="$evidence_dir/check"
    if [ "${1:-}" = "--require-release-evidence" ]; then
      evidence_scope="$evidence_dir"
    fi
    if ! find "$evidence_scope" -type f -name "*.meta" -print -quit 2>/dev/null | grep -q .; then
      echo "review-report check failed: no recorded validation evidence" >&2
      exit 1
    fi
    if find "$evidence_scope" -type f -name "*.meta" -exec awk -F= '$1 == "exit_code" && $2 != "0" { bad=1 } END { exit bad ? 0 : 1 }' {} \; -print \
      2>/dev/null | grep -q .; then
      echo "review-report check failed: validation evidence contains failed commands" >&2
      exit 1
    fi
    current_fingerprint="$(python3 scripts/worktree-fingerprint.py)"
    if find "$evidence_scope" -type f -name "*.meta" -exec awk -F= -v expected="$current_fingerprint" \
      '$1 == "worktree_fingerprint" { found=1; if ($2 != expected) bad=1 } END { exit (!found || bad) ? 0 : 1 }' {} \; -print \
      2>/dev/null | grep -q .; then
      echo "review-report check failed: validation evidence is stale for the current worktree" >&2
      exit 1
    fi
  fi
  echo "review-report check passed."
  exit 0
fi

generate_report
