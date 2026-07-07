#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install_report="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT:-$component_dir/build/local-app-install/local-app-install-report.json}"
recording_report="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_REPORT:-$component_dir/build/local-direct-recording-smoke/local-direct-recording-smoke-report.json}"
report_dir="${MA_NATIVE_LOCAL_APP_PERMISSION_DIAGNOSTICS_REPORT_DIR:-$component_dir/build/local-app-permission-diagnostics}"
report_file="${MA_NATIVE_LOCAL_APP_PERMISSION_DIAGNOSTICS_REPORT:-$report_dir/local-app-permission-diagnostics-report.json}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-app-permission-diagnostics.sh [options]

Read the local app install report and the latest local-direct recording smoke
report, then write a machine-readable diagnostic that identifies the exact
installed app path and codesign CDHash that should be authorized by the user.

Options:
  --install-report PATH   Read this local app install report.
  --recording-report PATH Read this local-direct recording smoke report.
  --report-file PATH      Write diagnostics JSON to this file.
  --help                  Show this help.

This script is read-only. It does not open System Settings, modify TCC, or
require Developer ID, notarization, stapling, Sigstore, or App Store distribution.
USAGE
}

resolve_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-report)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --install-report requires a path" >&2
        exit 2
      fi
      install_report="$2"
      shift 2
      ;;
    --recording-report)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --recording-report requires a path" >&2
        exit 2
      fi
      recording_report="$2"
      shift 2
      ;;
    --report-file)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --report-file requires a path" >&2
        exit 2
      fi
      report_file="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

install_report="$(resolve_path "$install_report")"
recording_report="$(resolve_path "$recording_report")"
report_file="$(resolve_path "$report_file")"

mkdir -p "$(dirname "$report_file")"

python3 - "$install_report" "$recording_report" "$report_file" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

install_report_path = Path(sys.argv[1])
recording_report_path = Path(sys.argv[2])
report_file = Path(sys.argv[3])


def load_json(path: Path, *, required: bool) -> dict[str, Any]:
    if not path.is_file():
        if required:
            raise SystemExit(f"required report is missing: {path}")
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"report must be a JSON object: {path}")
    return payload


install_report = load_json(install_report_path, required=True)
recording_report = load_json(recording_report_path, required=False)

installed_app = install_report.get("installed_app")
if not isinstance(installed_app, dict):
    raise SystemExit(f"install report is missing installed_app object: {install_report_path}")
installed_path = str(installed_app.get("path", "")).strip()
if not installed_path:
    raise SystemExit(f"install report is missing installed_app.path: {install_report_path}")

local_tcc_identity_strategy = str(install_report.get("local_tcc_identity_strategy", "")).strip()

codesign = installed_app.get("codesign")
if not isinstance(codesign, dict):
    codesign = {}
installed_cdhash = str(codesign.get("CDHash", "")).strip()

recording_app = recording_report.get("app_identity")
if not isinstance(recording_app, dict):
    recording_app = {}
recording_path = str(recording_app.get("path", "")).strip()
recording_codesign = recording_app.get("codesign")
if not isinstance(recording_codesign, dict):
    recording_codesign = {}
recording_cdhash = str(recording_codesign.get("CDHash", "")).strip()

permission_details = recording_report.get("permission_failure_details")
if not isinstance(permission_details, list):
    permission_details = []
permission_text = "\n".join(str(item) for item in permission_details)
screen_recording_denied = "Screen Recording permission is denied" in permission_text
same_app_as_recording_smoke = (
    bool(recording_path)
    and recording_path == installed_path
    and (not installed_cdhash or not recording_cdhash or recording_cdhash == installed_cdhash)
)

recommended_target = {
    "path": installed_path,
    "CFBundleIdentifier": installed_app.get("CFBundleIdentifier", ""),
    "CFBundleName": installed_app.get("CFBundleName", ""),
    "CFBundleDisplayName": installed_app.get("CFBundleDisplayName", ""),
    "CDHash": installed_cdhash,
    "Signature": codesign.get("Signature", ""),
    "TeamIdentifier": codesign.get("TeamIdentifier", ""),
}

report = {
    "report_schema": 1,
    "release_gate": "local-app-permission-diagnostics",
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "install_report": str(install_report_path),
    "recording_report": str(recording_report_path) if recording_report else "",
    "recommended_tcc_target": recommended_target,
    "recording_smoke_app_identity": recording_app,
    "same_app_as_recording_smoke": same_app_as_recording_smoke,
    "screen_recording_permission_denied": screen_recording_denied,
    "permission_failure_details": permission_details,
    "local_tcc_identity_strategy": local_tcc_identity_strategy,
    "user_action_required": screen_recording_denied or not same_app_as_recording_smoke,
    "user_action_summary": (
        "Grant Screen Recording / Screen & System Audio Recording to the recommended_tcc_target.path, "
        "then rerun recommended_recording_smoke_command."
    ),
    "recommended_visible_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{installed_path}" '
        "./platform/native-app/scripts/local-direct-smoke.sh --no-build"
    ),
    "recommended_recording_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{installed_path}" '
        "./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build"
    ),
    "recommended_direct_recording_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{installed_path}" '
        "MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct "
        "./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build"
    ),
    "direct_launch_diagnostic": (
        "Use only to separate local capture functionality from LaunchServices/TCC attribution; "
        "the default local user path remains LaunchServices open."
    ),
    "opens_system_settings": False,
    "modifies_tcc_or_system_settings": False,
    "requires_developer_id_or_notarization": False,
    "requires_app_store_distribution": False,
    "not_release_readiness": True,
}

report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("local app permission diagnostics:")
print(f"  target: {installed_path}")
print(f"  display name: {installed_app.get('CFBundleDisplayName', '') or installed_app.get('CFBundleName', '') or 'unknown'}")
print(f"  cdhash: {installed_cdhash or 'unknown'}")
print(f"  screen recording denied: {str(screen_recording_denied).lower()}")
print(f"  same app as recording smoke: {str(same_app_as_recording_smoke).lower()}")
print("  direct diagnostic: MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct ./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build")
print(f"  report: {report_file}")
PY
