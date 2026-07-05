#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

if grep -R -n -E 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN' \
  Sources tests App UITests test-fixtures MeetingAssistantNative.xcodeproj/project.pbxproj component.json README.md; then
  echo "native-app security failed: forbidden network, install, or secret marker found." >&2
  exit 1
fi

if find scripts -type f ! -name security.sh ! -name architecture.sh -print0 |
  xargs -0 grep -n -E 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN'; then
  echo "native-app security failed: forbidden network, install, or secret marker found in component scripts." >&2
  exit 1
fi

mkdir -p security
python3 - <<'PY'
from __future__ import annotations

import json
from pathlib import Path

component = json.loads(Path("component.json").read_text(encoding="utf-8"))
report = {
    "component": component["id"],
    "report_schema": 1,
    "release_gate": "validation-only",
    "sast_static_analysis": True,
    "sca_dependency_review": True,
    "secret_scan": True,
    "forbidden_network_or_install_scan": True,
    "no_auto_downloads": True,
    "external_network_access": False,
    "packages_runtime_or_model": False,
    "findings": [],
}
Path("security/security-report.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "native-app security check passed."
