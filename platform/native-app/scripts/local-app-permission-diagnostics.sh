#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"

install_report="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT:-$component_dir/build/local-app-install/local-app-install-report.json}"
recording_report="${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_REPORT:-}"
recording_report_explicit="0"
if [[ -n "${MA_NATIVE_LOCAL_APP_RECORDING_SMOKE_REPORT:-}" ]]; then
  recording_report_explicit="1"
fi
# Include e2e release-local-direct-target-smoke same-chain reports, because
# local-functional failures are recorded there rather than in native-app/build.
recording_report_search_roots="${MA_NATIVE_LOCAL_APP_RECORDING_REPORT_SEARCH_ROOTS:-$component_dir/build:$root_dir/platform/e2e/build}"
report_dir="${MA_NATIVE_LOCAL_APP_PERMISSION_DIAGNOSTICS_REPORT_DIR:-$component_dir/build/local-app-permission-diagnostics}"
report_file="${MA_NATIVE_LOCAL_APP_PERMISSION_DIAGNOSTICS_REPORT:-$report_dir/local-app-permission-diagnostics-report.json}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/local-app-permission-diagnostics.sh [options]

Read the local app install report and the latest local-direct recording smoke
report, then write a machine-readable diagnostic that identifies the exact
installed app path and stable codesign requirement that should be authorized by
the user.

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

latest_recording_report() {
  python3 - "$recording_report_search_roots" <<'PY'
from pathlib import Path
import os
import sys

roots = [Path(item).expanduser() for item in sys.argv[1].split(os.pathsep) if item]
candidates: list[Path] = []
for root in roots:
    if not root.exists():
        continue
    candidates.extend(
        path
        for path in root.rglob("local-direct-recording-smoke-report.json")
        if path.is_file()
    )

if not candidates:
    raise SystemExit(1)

latest = max(candidates, key=lambda path: path.stat().st_mtime)
print(latest)
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
      recording_report_explicit="1"
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
if [[ -z "$recording_report" ]]; then
  recording_report="$(latest_recording_report || true)"
fi
if [[ -z "$recording_report" ]]; then
  recording_report="$component_dir/build/local-direct-recording-smoke/local-direct-recording-smoke-report.json"
fi
recording_report="$(resolve_path "$recording_report")"
report_file="$(resolve_path "$report_file")"

mkdir -p "$(dirname "$report_file")"

python3 - "$install_report" "$recording_report" "$report_file" "$recording_report_explicit" "$recording_report_search_roots" <<'PY'
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

install_report_path = Path(sys.argv[1])
recording_report_path = Path(sys.argv[2])
report_file = Path(sys.argv[3])
recording_report_explicit = sys.argv[4] == "1"
recording_report_search_roots = sys.argv[5]


def load_json(path: Path, *, required: bool) -> dict[str, Any]:
    if not path.is_file():
        if required:
            raise SystemExit(f"required report is missing: {path}")
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"report must be a JSON object: {path}")
    return payload


def load_candidate_report(path: Path) -> dict[str, Any]:
    try:
        return load_json(path, required=False)
    except (json.JSONDecodeError, OSError, SystemExit):
        return {}


def same_app_identity(
    report: dict[str, Any],
    *,
    installed_path: str,
    installed_cdhash: str,
    installed_requirement: str,
) -> bool:
    app = report.get("app_identity")
    if not isinstance(app, dict):
        return False
    path = str(app.get("path", "")).strip()
    if path != installed_path:
        return False
    codesign = app.get("codesign")
    if not isinstance(codesign, dict):
        codesign = {}
    cdhash = str(codesign.get("CDHash", "")).strip()
    requirement = str(codesign.get("DesignatedRequirement", "")).strip()
    if installed_requirement and requirement:
        return requirement == installed_requirement
    return not installed_cdhash or not cdhash or cdhash == installed_cdhash


def report_sort_key(path: Path) -> tuple[float, str]:
    try:
        return (path.stat().st_mtime, str(path))
    except OSError:
        return (0.0, str(path))


def matching_reports(
    *,
    installed_path: str,
    installed_cdhash: str,
    installed_requirement: str,
) -> tuple[Path | None, Path | None]:
    roots = [Path(item).expanduser() for item in recording_report_search_roots.split(os.pathsep) if item]
    candidates: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        candidates.extend(
            path
            for path in root.rglob("local-direct-recording-smoke-report.json")
            if path.is_file()
        )

    direct_success: list[Path] = []
    open_denied: list[Path] = []
    for path in candidates:
        report = load_candidate_report(path)
        if not report:
            continue
        if not same_app_identity(
            report,
            installed_path=installed_path,
            installed_cdhash=installed_cdhash,
            installed_requirement=installed_requirement,
        ):
            continue
        runner = report.get("runner_configuration")
        if not isinstance(runner, dict):
            runner = {}
        launch_mode = str(runner.get("launch_mode", "")).strip()
        if report.get("passed") is True and launch_mode == "direct":
            direct_success.append(path)
        if (
            report.get("passed") is False
            and launch_mode == "open"
            and report.get("blocker_type") == "permission_denied"
        ):
            open_denied.append(path)

    latest_direct = max(direct_success, key=report_sort_key) if direct_success else None
    latest_open_denied = max(open_denied, key=report_sort_key) if open_denied else None
    return latest_direct, latest_open_denied


install_report = load_json(install_report_path, required=True)
recording_report = load_json(recording_report_path, required=False)

installed_app = install_report.get("installed_app")
if not isinstance(installed_app, dict):
    raise SystemExit(f"install report is missing installed_app object: {install_report_path}")
installed_path = str(installed_app.get("path", "")).strip()
if not installed_path:
    raise SystemExit(f"install report is missing installed_app.path: {install_report_path}")

local_tcc_identity_strategy = str(install_report.get("local_tcc_identity_strategy", "")).strip()
local_signing = install_report.get("local_signing")
if not isinstance(local_signing, dict):
    local_signing = {}

codesign = installed_app.get("codesign")
if not isinstance(codesign, dict):
    codesign = {}
installed_cdhash = str(codesign.get("CDHash", "")).strip()
installed_requirement = str(codesign.get("DesignatedRequirement", "")).strip()

recording_app = recording_report.get("app_identity")
if not isinstance(recording_app, dict):
    recording_app = {}
recording_path = str(recording_app.get("path", "")).strip()
recording_codesign = recording_app.get("codesign")
if not isinstance(recording_codesign, dict):
    recording_codesign = {}
recording_cdhash = str(recording_codesign.get("CDHash", "")).strip()
recording_requirement = str(recording_codesign.get("DesignatedRequirement", "")).strip()

permission_details = recording_report.get("permission_failure_details")
if not isinstance(permission_details, list):
    permission_details = []
permission_text = "\n".join(str(item) for item in permission_details)
screen_recording_denied = (
    "Screen Recording permission is denied" in permission_text
    or recording_report.get("blocker_type") == "permission_denied"
)
same_app_as_recording_smoke = (
    bool(recording_path)
    and recording_path == installed_path
    and (
        (
            bool(installed_requirement)
            and bool(recording_requirement)
            and recording_requirement == installed_requirement
        )
        or (
            (not installed_requirement or not recording_requirement)
            and (not installed_cdhash or not recording_cdhash or recording_cdhash == installed_cdhash)
        )
    )
)
latest_direct_success_report, latest_open_permission_denied_report = matching_reports(
    installed_path=installed_path,
    installed_cdhash=installed_cdhash,
    installed_requirement=installed_requirement,
)
launchservices_tcc_attribution_suspected = bool(
    latest_direct_success_report and latest_open_permission_denied_report
)

recommended_target = {
    "path": installed_path,
    "CFBundleIdentifier": installed_app.get("CFBundleIdentifier", ""),
    "CFBundleName": installed_app.get("CFBundleName", ""),
    "CFBundleDisplayName": installed_app.get("CFBundleDisplayName", ""),
    "CDHash": installed_cdhash,
    "Signature": codesign.get("Signature", ""),
    "TeamIdentifier": codesign.get("TeamIdentifier", ""),
    "Authority": codesign.get("Authority", ""),
    "DesignatedRequirement": installed_requirement,
    "local_signing": {
        "mode": local_signing.get("mode", ""),
        "identity_name": local_signing.get("identity_name", ""),
        "identity_hash": local_signing.get("identity_hash", ""),
        "stable_tcc_identity": local_signing.get("stable_tcc_identity", False),
    },
}

report = {
    "report_schema": 1,
    "release_gate": "local-app-permission-diagnostics",
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "install_report": str(install_report_path),
    "recording_report": str(recording_report_path) if recording_report else "",
    "recording_report_selection": "explicit" if recording_report_explicit else "latest",
    "recording_report_found": bool(recording_report),
    "recommended_tcc_target": recommended_target,
    "recording_smoke_app_identity": recording_app,
    "same_app_as_recording_smoke": same_app_as_recording_smoke,
    "screen_recording_permission_denied": screen_recording_denied,
    "latest_matching_direct_success_recording_report": (
        str(latest_direct_success_report.resolve()) if latest_direct_success_report else ""
    ),
    "latest_matching_open_permission_denied_recording_report": (
        str(latest_open_permission_denied_report.resolve()) if latest_open_permission_denied_report else ""
    ),
    "launchservices_tcc_attribution_suspected": launchservices_tcc_attribution_suspected,
    "launchservices_tcc_attribution_summary": (
        "A direct executable launch succeeded for the same installed app identity while LaunchServices open "
        "was denied; re-add recommended_tcc_target.path in Screen Recording / Screen & System Audio Recording."
        if launchservices_tcc_attribution_suspected
        else ""
    ),
    "permission_failure_details": permission_details,
    "local_tcc_identity_strategy": local_tcc_identity_strategy,
    "stable_tcc_identity": bool(local_signing.get("stable_tcc_identity", False)),
    "user_action_required": (
        screen_recording_denied
        or not same_app_as_recording_smoke
        or launchservices_tcc_attribution_suspected
    ),
    "user_action_summary": (
        "Grant Screen Recording / Screen & System Audio Recording to the recommended_tcc_target.path "
        "for the reported DesignatedRequirement, then rerun recommended_recording_smoke_command."
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
print(f"  designated requirement: {installed_requirement or 'unknown'}")
print(f"  stable tcc identity: {str(bool(local_signing.get('stable_tcc_identity', False))).lower()}")
print(f"  screen recording denied: {str(screen_recording_denied).lower()}")
print(f"  same app as recording smoke: {str(same_app_as_recording_smoke).lower()}")
print(f"  launchservices/tcc attribution suspected: {str(launchservices_tcc_attribution_suspected).lower()}")
print("  direct diagnostic: MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct ./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build")
print(f"  report: {report_file}")
PY
