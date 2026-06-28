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
  "scripts/product-validation-check.py"
  "scripts/production-readiness-check.sh"
  "scripts/phase-preflight.sh"
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

  stale_project_state_pattern='当前仓库处于 `adoption` 模式|当前项目处于 adoption/spec-review|当前 adoption 阶段允许|用户尚未审查完整持久 spec|尚未提供 product-spec 审查|仍等待用户审查|仍需用户 spec-review|等待用户.*activation|用户 spec 审查[[:space:]]*\|[[:space:]]*等待用户操作|Project activation 批准[[:space:]]*\|[[:space:]]*等待用户显式批准|用户是否已审查 product-spec[[:space:]]*\|[[:space:]]*no|用户是否已显式批准 project activation[[:space:]]*\|[[:space:]]*no'
  if grep -n -E "$stale_project_state_pattern" \
    README.md \
    docs/product-spec/README.md \
    docs/product-spec/10-open-decisions.md \
    docs/adoption/SPEC-READINESS.md \
    docs/adoption/DISCOVERY-LEDGER.md \
    platform/README.md 2>/dev/null; then
    fail "project mode contains stale adoption/spec-review or activation-pending wording"
  fi

  current_mode_restatement_pattern='当前(仓库|项目)[^[:cntrl:]]*(framework|adoption|project)[^[:cntrl:]]*模式|当前 `project` 模式|当前 `adoption` 模式|当前 `framework` 模式|本仓库已经完成 project activation|当前 Activation 状态|当前 Discovery 轮次'
  if grep -n -E "$current_mode_restatement_pattern" \
    README.md \
    docs/product-spec/README.md \
    docs/product-spec/10-open-decisions.md \
    docs/engineering/14-greenfield-project-start.md \
    docs/adoption/README.md \
    docs/adoption/SPEC-READINESS.md \
    docs/adoption/DISCOVERY-LEDGER.md \
    platform/README.md 2>/dev/null; then
    fail "current project mode must only be declared in docs/product-spec/PROJECT-STATUS.md"
  fi

  stale_activation_boundary_pattern='activation 前允许|activation 前的组件骨架|activation 阶段允许存在|本目录只提供 activation 阶段|当前 `project` 模式下已经存在|在 MVP activation 前'
  if grep -n -E "$stale_activation_boundary_pattern" \
    docs/product-spec/04-user-journeys-and-ui.md \
    docs/product-spec/09-acceptance-criteria.md \
    docs/engineering/01-repo-structure.md \
    docs/engineering/02-dev-commands.md \
    docs/engineering/10-security-and-supply-chain.md \
    platform/README.md \
    platform/native-app/README.md \
    platform/processing-cli/README.md \
    platform/e2e/README.md 2>/dev/null; then
    fail "project mode contains stale activation-boundary wording outside historical audit docs"
  fi

  manifest_command_table_pattern='^\|[[:space:]]*`?(native-app|processing-cli|full-stack-e2e)`?[[:space:]]*\|[[:space:]]*(lint|test|build|architecture|security|sbom|smoke)[[:space:]]*\|'
  if grep -n -E "$manifest_command_table_pattern" \
    docs/engineering/01-repo-structure.md \
    docs/engineering/02-dev-commands.md \
    platform/README.md 2>/dev/null; then
    fail "component command rows must be read from harness/project-manifest.json"
  fi

  python3 - <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"docs-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def table_rows(path: Path, prefix: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped.startswith(f"| {prefix}"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if cells:
            rows.append(cells)
    return rows


def ids(text: str, prefix: str) -> set[str]:
    return set(re.findall(rf"\b{re.escape(prefix)}-\d{{3}}\b", text))


scope = Path("docs/product-spec/01-product-scope.md")
acceptance = Path("docs/product-spec/09-acceptance-criteria.md")
validation = Path("docs/engineering/06-product-validation-matrix.md")

cap_rows = table_rows(scope, "CAP-MA-")
ac_rows = table_rows(acceptance, "AC-MA-")
pv_rows = table_rows(validation, "PV-MA-")

cap_list = [row[0] for row in cap_rows]
ac_list = [row[0] for row in ac_rows]
pv_list = [row[0] for row in pv_rows]
cap_ids = set(cap_list)
ac_ids = set(ac_list)
pv_ids = set(pv_list)

if not cap_ids:
    fail("project mode requires CAP-MA product capability rows in docs/product-spec/01-product-scope.md")
if not ac_ids:
    fail("project mode requires AC-MA acceptance rows in docs/product-spec/09-acceptance-criteria.md")
if not pv_ids:
    fail("project mode requires PV-MA validation rows in docs/engineering/06-product-validation-matrix.md")

for name, values in (("CAP-MA", cap_list), ("AC-MA", ac_list), ("PV-MA", pv_list)):
    if len(values) != len(set(values)):
        fail(f"duplicate {name} IDs are not allowed")

cap_to_ac: dict[str, set[str]] = {}
cap_to_pv: dict[str, set[str]] = {}
for row in cap_rows:
    cap_id = row[0]
    text = " ".join(row)
    ac_refs = ids(text, "AC-MA")
    pv_refs = ids(text, "PV-MA")
    if not ac_refs:
        fail(f"{cap_id} must reference at least one AC-MA acceptance row")
    if not pv_refs:
        fail(f"{cap_id} must reference at least one PV-MA validation row")
    missing_ac = sorted(ac_refs - ac_ids)
    missing_pv = sorted(pv_refs - pv_ids)
    if missing_ac:
        fail(f"{cap_id} references missing acceptance rows: {', '.join(missing_ac)}")
    if missing_pv:
        fail(f"{cap_id} references missing validation rows: {', '.join(missing_pv)}")
    cap_to_ac[cap_id] = ac_refs
    cap_to_pv[cap_id] = pv_refs

referenced_ac = set().union(*cap_to_ac.values())
referenced_pv = set().union(*cap_to_pv.values())
missing_cap_for_ac = sorted(ac_ids - referenced_ac)
missing_cap_for_pv = sorted(pv_ids - referenced_pv)
if missing_cap_for_ac:
    fail(f"AC-MA rows must be reachable from CAP-MA capability matrix: {', '.join(missing_cap_for_ac)}")
if missing_cap_for_pv:
    fail(f"PV-MA rows must be reachable from CAP-MA capability matrix: {', '.join(missing_cap_for_pv)}")

for row in ac_rows:
    ac_id = row[0]
    pv_refs = ids(" ".join(row), "PV-MA")
    if not pv_refs:
        fail(f"{ac_id} must reference at least one PV-MA validation row")
    missing_pv = sorted(pv_refs - pv_ids)
    if missing_pv:
        fail(f"{ac_id} references missing validation rows: {', '.join(missing_pv)}")

for row in pv_rows:
    pv_id = row[0]
    cap_refs = ids(" ".join(row), "CAP-MA")
    if not cap_refs:
        fail(f"{pv_id} must reference at least one CAP-MA capability row")
    missing_cap = sorted(cap_refs - cap_ids)
    if missing_cap:
        fail(f"{pv_id} references missing capability rows: {', '.join(missing_cap)}")
PY
fi

python3 scripts/action-pin-check.py
./scripts/project-manifest-check.sh current

echo "docs-check passed."
