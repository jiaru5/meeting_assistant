#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"

default_source_app="$root_dir/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app"
install_dir="${MA_NATIVE_LOCAL_APP_INSTALL_DIR:-$HOME/Applications}"
install_path="${MA_NATIVE_LOCAL_APP_INSTALL_PATH:-$install_dir/MeetingAssistantNative.app}"
source_app="${MA_NATIVE_LOCAL_APP_SOURCE_APP:-$default_source_app}"
report_dir="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT_DIR:-$component_dir/build/local-app-install}"
report_file="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT:-$report_dir/local-app-install-report.json}"
build_if_missing="${MA_NATIVE_LOCAL_APP_BUILD_IF_MISSING:-1}"
rebuild="${MA_NATIVE_LOCAL_APP_REBUILD:-0}"
dry_run="${MA_NATIVE_LOCAL_APP_DRY_RUN:-0}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/install-local-app.sh [options]

Build or reuse the local-direct Release MeetingAssistantNative.app and install it
to a stable user-owned app path, defaulting to ~/Applications/MeetingAssistantNative.app.

Options:
  --source-app PATH    Copy from an existing MeetingAssistantNative.app bundle.
  --install-path PATH  Install to this exact .app path.
  --install-dir DIR    Install as MeetingAssistantNative.app inside DIR.
  --report-file PATH   Write the install identity report to this JSON file.
  --no-build           Require the source app bundle to already exist.
  --rebuild            Rebuild the local-direct Release app before installing.
  --dry-run            Print the resolved install plan without copying.
  --help               Show this help.

This script does not open System Settings, modify TCC, or require Developer ID,
notarization, stapling, Sigstore, or App Store distribution.
USAGE
}

is_truthy() {
  case "${1:-0}" in
    1 | true | TRUE | yes | YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

plist_value() {
  local app="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist" 2>/dev/null
}

require_meeting_assistant_app() {
  local app="$1"
  if [[ ! -d "$app" ]]; then
    echo "error: app bundle does not exist: $app" >&2
    exit 1
  fi
  if [[ ! -f "$app/Contents/Info.plist" ]]; then
    echo "error: app bundle is missing Contents/Info.plist: $app" >&2
    exit 1
  fi
  local bundle_id
  local bundle_name
  bundle_id="$(plist_value "$app" "CFBundleIdentifier" || true)"
  bundle_name="$(plist_value "$app" "CFBundleName" || true)"
  if [[ "$bundle_id" != "local.meeting-assistant.native" ]]; then
    echo "error: expected CFBundleIdentifier local.meeting-assistant.native, got ${bundle_id:-missing}: $app" >&2
    exit 1
  fi
  if [[ "$bundle_name" != "MeetingAssistantNative" ]]; then
    echo "error: expected CFBundleName MeetingAssistantNative, got ${bundle_name:-missing}: $app" >&2
    exit 1
  fi
  if [[ ! -x "$app/Contents/MacOS/MeetingAssistantNative" ]]; then
    echo "error: app executable is missing or not executable: $app/Contents/MacOS/MeetingAssistantNative" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-app)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --source-app requires a path" >&2
        exit 2
      fi
      source_app="$2"
      shift 2
      ;;
    --install-path)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --install-path requires a path" >&2
        exit 2
      fi
      install_path="$2"
      shift 2
      ;;
    --install-dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --install-dir requires a path" >&2
        exit 2
      fi
      install_dir="$2"
      install_path="$install_dir/MeetingAssistantNative.app"
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
    --no-build)
      build_if_missing="0"
      shift
      ;;
    --rebuild)
      rebuild="1"
      shift
      ;;
    --dry-run)
      dry_run="1"
      shift
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

source_app="$(resolve_path "$source_app")"
install_path="$(resolve_path "$install_path")"
report_file="$(resolve_path "$report_file")"
install_dir="$(dirname "$install_path")"

if [[ "${install_path##*.}" != "app" ]]; then
  echo "error: --install-path must end with .app: $install_path" >&2
  exit 2
fi

if is_truthy "$rebuild" || { [[ ! -d "$source_app" ]] && is_truthy "$build_if_missing"; }; then
  "$root_dir/scripts/release-bundle-create.py" \
    --distribution-mode local-direct \
    --builder "${MEETING_ASSISTANT_RELEASE_BUILDER:-local-direct-app-install}" \
    --source-repository "${MEETING_ASSISTANT_RELEASE_SOURCE_REPOSITORY:-local/meeting_assistant}"
fi

require_meeting_assistant_app "$source_app"

if [[ -e "$install_path" ]]; then
  require_meeting_assistant_app "$install_path"
fi

echo "MeetingAssistantNative local install:"
echo "  source: $source_app"
echo "  install: $install_path"
echo "  report: $report_file"
echo "  distribution mode: local-direct"
echo "  modifies tcc or system settings: false"
echo "  requires developer id or notarization: false"

if is_truthy "$dry_run"; then
  echo "dry run: app not copied"
  exit 0
fi

mkdir -p "$install_dir"
tmp_app="$install_dir/.MeetingAssistantNative.app.install.$$"
rm -rf "$tmp_app"
trap 'rm -rf "$tmp_app"' EXIT INT TERM

/usr/bin/ditto "$source_app" "$tmp_app"
require_meeting_assistant_app "$tmp_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$tmp_app" >/dev/null

if [[ -e "$install_path" ]]; then
  rm -rf "$install_path"
fi
mv "$tmp_app" "$install_path"
trap - EXIT INT TERM

mkdir -p "$(dirname "$report_file")"
python3 - "$source_app" "$install_path" "$report_file" <<'PY'
from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

source_app = Path(sys.argv[1])
install_app = Path(sys.argv[2])
report_file = Path(sys.argv[3])


def info_plist(app: Path) -> dict[str, object]:
    with (app / "Contents/Info.plist").open("rb") as handle:
        return plistlib.load(handle)


def codesign_details(app: Path) -> dict[str, str]:
    completed = subprocess.run(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(app)],
        text=True,
        capture_output=True,
        check=False,
    )
    output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        raise SystemExit(f"codesign details failed for {app}: {output.strip()}")
    details: dict[str, str] = {}
    for key in ("Identifier", "Format", "CDHash", "Signature", "TeamIdentifier"):
        match = re.search(rf"(?m)^{key}=(.+)$", output)
        if match:
            details[key] = match.group(1).strip()
    return details


plist = info_plist(install_app)
report = {
    "report_schema": 1,
    "release_gate": "local-direct-app-install",
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "source_app": str(source_app),
    "installed_app": {
        "path": str(install_app),
        "CFBundleIdentifier": plist.get("CFBundleIdentifier", ""),
        "CFBundleName": plist.get("CFBundleName", ""),
        "CFBundleShortVersionString": plist.get("CFBundleShortVersionString", ""),
        "codesign": codesign_details(install_app),
    },
    "distribution_mode": "local-direct",
    "install_method": "user-applications-copy",
    "opens_system_settings": False,
    "modifies_tcc_or_system_settings": False,
    "requires_developer_id_or_notarization": False,
    "requires_app_store_distribution": False,
    "not_release_readiness": True,
    "recommended_visible_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{install_app}" '
        "./platform/native-app/scripts/local-direct-smoke.sh --no-build"
    ),
    "recommended_recording_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{install_app}" '
        "./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build"
    ),
    "recommended_direct_recording_smoke_command": (
        f'MA_NATIVE_LOCAL_APP_PATH="{install_app}" '
        "MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct "
        "./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build"
    ),
    "direct_launch_diagnostic": (
        "Use only to distinguish local capture functionality from LaunchServices/TCC attribution; "
        "the default local app path remains LaunchServices open."
    ),
}
report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "local app installed: $install_path"
echo "report: $report_file"
echo "run with: MA_NATIVE_LOCAL_APP_PATH=\"$install_path\" ./platform/native-app/scripts/run-local-app.sh --no-build"
echo "direct recording diagnostic: MA_NATIVE_LOCAL_APP_PATH=\"$install_path\" MA_NATIVE_LOCAL_APP_LAUNCH_MODE=direct ./platform/native-app/scripts/local-direct-recording-smoke.sh --no-build"
