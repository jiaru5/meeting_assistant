#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "docs-check failed: $1" >&2
  exit 1
}

required_files=(
  "AGENTS.md"
  "README.md"
  "SECURITY.md"
  "harness/project-manifest.json"
  "harness/agent-policy.json"
  "harness/adoption-state.json"
  "harness/evals/cases.json"
  "docs/adoption/README.md"
  "docs/adoption/INITIAL-REQUEST.md"
  "docs/adoption/DISCOVERY-LEDGER.md"
  "docs/adoption/SPEC-READINESS.md"
  "docs/product-spec/PROJECT-STATUS.md"
  "docs/product-spec/README.md"
  "docs/product-spec/00-governance.md"
  "docs/product-spec/01-product-scope.md"
  "docs/product-spec/02-domain-model.md"
  "docs/product-spec/03-permissions-and-identity.md"
  "docs/product-spec/04-user-journeys-and-ui.md"
  "docs/product-spec/05-business-rules-and-calculations.md"
  "docs/product-spec/06-api-contracts.md"
  "docs/product-spec/07-data-and-events.md"
  "docs/product-spec/08-implementation-guidance.md"
  "docs/product-spec/09-acceptance-criteria.md"
  "docs/product-spec/10-open-decisions.md"
  "docs/product-spec/11-adr.md"
  "docs/product-spec/12-ui-ux-design.md"
  "docs/product-spec/13-security-and-compliance.md"
  "docs/engineering/README.md"
  "docs/engineering/01-repo-structure.md"
  "docs/engineering/02-dev-commands.md"
  "docs/engineering/03-test-strategy.md"
  "docs/engineering/04-review-and-ci-gates.md"
  "docs/engineering/05-agent-operating-model.md"
  "docs/engineering/06-product-validation-matrix.md"
  "docs/engineering/07-development-plan.md"
  "docs/engineering/08-service-standards.md"
  "docs/engineering/09-starter-adoption-guide.md"
  "docs/engineering/10-security-and-supply-chain.md"
  "docs/engineering/11-production-readiness.md"
  "docs/engineering/12-agent-security.md"
  "docs/engineering/13-harness-evaluation.md"
  "docs/engineering/14-greenfield-project-start.md"
)

for file in "${required_files[@]}"; do
  [ -f "$file" ] || fail "missing required file: $file"
done

required_executable_files=(
  "scripts/agent-workflow-check.sh"
  "scripts/activate-project.sh"
  "scripts/adoption-check.sh"
  "scripts/adoption-status.sh"
  "scripts/adoption-runtime.py"
  "scripts/agent-eval-check.py"
  "scripts/architecture-check.sh"
  "scripts/compose-check.sh"
  "scripts/db-migration-check.sh"
  "scripts/harness-self-test.sh"
  "scripts/project-manifest-check.sh"
  "scripts/prod-config-check.sh"
  "scripts/production-readiness-check.sh"
  "scripts/release-preflight.sh"
  "scripts/review-report.sh"
  "scripts/security-check.sh"
  "scripts/spec-sync-check.sh"
  "scripts/start-project.sh"
  "scripts/supply-chain-check.sh"
  "scripts/worktree-fingerprint.py"
)

for file in "${required_executable_files[@]}"; do
  [ -x "$file" ] || fail "missing executable workflow file: $file"
done

check_index() {
  local dir="$1"
  local index_file="$2"
  local file base

  while IFS= read -r file; do
    base="$(basename "$file")"
    [ "$base" = "README.md" ] && continue
    if ! grep -F -q "\`$base\`" "$index_file"; then
      fail "missing $base in $index_file index"
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name "*.md" | sort)
}

check_index "docs/product-spec" "docs/product-spec/README.md"
check_index "docs/engineering" "docs/engineering/README.md"
check_index "docs/adoption" "docs/adoption/README.md"

if find docs -type f -name "*.md" \
  ! -path "docs/adoption/*" \
  ! -path "docs/product-spec/*" \
  ! -path "docs/engineering/*" \
  -print | grep -q .; then
  fail "reference docs must live under docs/adoption, docs/product-spec or docs/engineering"
fi

if grep -R --exclude=docs-check.sh -n -E "SMARTTEAM-PRD-TECH-DESIGN|docs/smartteam-spec" \
  AGENTS.md README.md docs scripts .github docker-compose*.yml 2>/dev/null; then
  fail "found stale example-specific fact-source wording"
fi

if grep -R --exclude=docs-check.sh -n -E "brew services|localhost:5432|本机 PostgreSQL|宿主机 PostgreSQL" \
  AGENTS.md README.md docs scripts docker-compose*.yml 2>/dev/null; then
  fail "found forbidden host database or middleware dependency wording"
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts -maxdepth 1 -type f -name "*.sh" | sort)

project_mode="$(
  awk -F: '
    /^[[:space:]]*mode[[:space:]]*:/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' docs/product-spec/PROJECT-STATUS.md
)"

case "$project_mode" in
  framework|adoption|project)
    ;;
  *)
    fail "docs/product-spec/PROJECT-STATUS.md must declare mode: framework, adoption, or project"
    ;;
esac

if [ "$project_mode" = "project" ]; then
  placeholder_pattern='EXAMPLE_ONLY|PLACEHOLDER|EntityName|EntityStatus|EntitySummaryView|GOAL-001|NOGOAL-001|ROLE-001|SCN-001|BC-001|DM-INV-001|PERM-001|PERM-002|UI-001|UI-002|JRN-001|RULE-STATE-001|RULE-CALC-001|RULE-TIME-001|/api/entities|example-service|EVT-001|AC-001|AC-002|OD-001|PV-AREA-001|SEC-REQ-001|DATA-CLASS-001|THREAT-001'
  if grep -R --exclude=PROJECT-STATUS.md -n -E "$placeholder_pattern" \
    docs/product-spec docs/engineering/06-product-validation-matrix.md 2>/dev/null; then
    fail "project mode cannot contain starter example placeholders"
  fi
fi

python3 scripts/action-pin-check.py
./scripts/project-manifest-check.sh current

echo "docs-check passed."
