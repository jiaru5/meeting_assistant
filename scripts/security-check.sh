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

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "harness/project-manifest.json").read_text(encoding="utf-8"))

for component in manifest.get("components", []):
    if not isinstance(component, dict) or component.get("production") is not True:
        continue
    component_path = component.get("path")
    if isinstance(component_path, str):
        report_path = root / component_path / "security/security-report.json"
        report_path.unlink(missing_ok=True)
PY

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

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "harness/project-manifest.json").read_text(encoding="utf-8"))
failures: list[str] = []

for component in manifest.get("components", []):
    if not isinstance(component, dict) or component.get("production") is not True:
        continue

    component_id = component.get("id")
    component_path = component.get("path")
    if not isinstance(component_id, str) or not isinstance(component_path, str):
        continue

    report_path = root / component_path / "security/security-report.json"
    if not report_path.is_file():
        failures.append(f"missing security report for production component {component_id}: {report_path.relative_to(root)}")
        continue

    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        failures.append(f"invalid security report JSON for production component {component_id}: {exc}")
        continue
    if not isinstance(report, dict):
        failures.append(f"security report for production component {component_id} must be a JSON object")
        continue

    expected_values = {
        "component": component_id,
        "report_schema": 1,
        "release_gate": "validation-only",
        "sast_static_analysis": True,
        "sca_dependency_review": True,
        "secret_scan": True,
        "forbidden_network_or_install_scan": True,
        "no_auto_downloads": True,
        "external_network_access": False,
        "packages_runtime_or_model": False,
    }
    for key, expected in expected_values.items():
        if report.get(key) != expected:
            failures.append(
                f"security report for production component {component_id} must set {key}={expected!r}"
            )
    if report.get("findings") != []:
        failures.append(f"security report for production component {component_id} must report zero findings")

if failures:
    print("security evidence reports failed:", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    raise SystemExit(1)

print("security evidence reports passed.")
PY

echo "security-check passed."
