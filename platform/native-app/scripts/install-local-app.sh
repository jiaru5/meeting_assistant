#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd "$component_dir/../.." && pwd)"

default_source_app="$root_dir/.harness/release-build/native-app/DerivedData/Build/Products/Release/MeetingAssistantNative.app"
install_dir="${MA_NATIVE_LOCAL_APP_INSTALL_DIR:-$HOME/Applications}"
install_app_name="${MA_NATIVE_LOCAL_APP_INSTALL_APP_NAME:-MeetingAssistantNativeLocal}"
install_path="${MA_NATIVE_LOCAL_APP_INSTALL_PATH:-$install_dir/$install_app_name.app}"
source_app="${MA_NATIVE_LOCAL_APP_SOURCE_APP:-$default_source_app}"
report_dir="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT_DIR:-$component_dir/build/local-app-install}"
report_file="${MA_NATIVE_LOCAL_APP_INSTALL_REPORT:-$report_dir/local-app-install-report.json}"
build_if_missing="${MA_NATIVE_LOCAL_APP_BUILD_IF_MISSING:-1}"
rebuild="${MA_NATIVE_LOCAL_APP_REBUILD:-0}"
dry_run="${MA_NATIVE_LOCAL_APP_DRY_RUN:-0}"
source_bundle_id="local.meeting-assistant.native"
source_bundle_name="MeetingAssistantNative"
install_bundle_id="${MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_ID:-local.meeting-assistant.native.localdirect}"
install_bundle_name="${MA_NATIVE_LOCAL_APP_INSTALL_BUNDLE_NAME:-MeetingAssistantNativeLocal}"
install_display_name="${MA_NATIVE_LOCAL_APP_INSTALL_DISPLAY_NAME:-Meeting Assistant Native Local}"
local_signing_mode="${MA_NATIVE_LOCAL_APP_SIGNING_MODE:-stable-local}"
local_signing_identity_name="${MA_NATIVE_LOCAL_APP_SIGNING_IDENTITY_NAME:-Meeting Assistant Local Code Signing}"
local_signing_support_dir="${MA_NATIVE_LOCAL_APP_SIGNING_SUPPORT_DIR:-$HOME/Library/Application Support/MeetingAssistant/local-signing}"
local_signing_keychain="${MA_NATIVE_LOCAL_APP_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/meeting-assistant-local-signing.keychain-db}"
local_signing_password_file="${MA_NATIVE_LOCAL_APP_SIGNING_PASSWORD_FILE:-$local_signing_support_dir/keychain-password.txt}"

usage() {
  cat <<'USAGE'
Usage: platform/native-app/scripts/install-local-app.sh [options]

Build or reuse the local-direct Release MeetingAssistantNative.app and install it
to a stable user-owned app path, defaulting to ~/Applications/MeetingAssistantNativeLocal.app.

Options:
  --source-app PATH    Copy from an existing MeetingAssistantNative.app bundle.
  --install-path PATH  Install to this exact .app path.
  --install-dir DIR    Install as MeetingAssistantNativeLocal.app inside DIR.
  --report-file PATH   Write the install identity report to this JSON file.
  --no-build           Require the source app bundle to already exist.
  --rebuild            Rebuild the local-direct Release app before installing.
  --dry-run            Print the resolved install plan without copying.
  --help               Show this help.

This script rewrites only the copied local app's Info.plist identity to avoid
TCC confusion with Debug/XCUITest apps, then applies a stable local self-signed
code-signing identity by default. Set MA_NATIVE_LOCAL_APP_SIGNING_MODE=ad-hoc
only for low-level diagnostics where TCC persistence is not required.
It does not open System Settings, modify TCC, or require Developer ID,
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

require_app_identity() {
  local app="$1"
  local expected_bundle_id="$2"
  local expected_bundle_name="$3"
  local context="$4"
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
  if [[ "$bundle_id" != "$expected_bundle_id" ]]; then
    echo "error: expected $context CFBundleIdentifier $expected_bundle_id, got ${bundle_id:-missing}: $app" >&2
    exit 1
  fi
  if [[ "$bundle_name" != "$expected_bundle_name" ]]; then
    echo "error: expected $context CFBundleName $expected_bundle_name, got ${bundle_name:-missing}: $app" >&2
    exit 1
  fi
  if [[ ! -x "$app/Contents/MacOS/MeetingAssistantNative" ]]; then
    echo "error: app executable is missing or not executable: $app/Contents/MacOS/MeetingAssistantNative" >&2
    exit 1
  fi
}

require_source_app() {
  require_app_identity "$1" "$source_bundle_id" "$source_bundle_name" "source app"
}

require_installed_app() {
  require_app_identity "$1" "$install_bundle_id" "$install_bundle_name" "installed app"
}

require_existing_install_target() {
  local app="$1"
  if [[ ! -d "$app" ]]; then
    echo "error: app bundle does not exist: $app" >&2
    exit 1
  fi
  local bundle_id
  local bundle_name
  bundle_id="$(plist_value "$app" "CFBundleIdentifier" || true)"
  bundle_name="$(plist_value "$app" "CFBundleName" || true)"
  if [[ "$bundle_id" == "$source_bundle_id" && "$bundle_name" == "$source_bundle_name" ]]; then
    return 0
  fi
  if [[ "$bundle_id" == "$install_bundle_id" && "$bundle_name" == "$install_bundle_name" ]]; then
    return 0
  fi
  echo "error: existing install target is not a Meeting Assistant local app: $app" >&2
  echo "       got CFBundleIdentifier=${bundle_id:-missing} CFBundleName=${bundle_name:-missing}" >&2
  exit 1
}

plist_set_or_add_string() {
  local plist="$1"
  local key="$2"
  local value="$3"
  if ! /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist" >/dev/null
  fi
}

localize_installed_identity() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  plist_set_or_add_string "$plist" "CFBundleIdentifier" "$install_bundle_id"
  plist_set_or_add_string "$plist" "CFBundleName" "$install_bundle_name"
  plist_set_or_add_string "$plist" "CFBundleDisplayName" "$install_display_name"
}

password_file_value() {
  local password_file="$1"
  if [[ ! -f "$password_file" ]]; then
    return 1
  fi
  python3 - "$password_file" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text(encoding="utf-8").strip())
PY
}

write_new_password_file() {
  local password_file="$1"
  mkdir -p "$(dirname "$password_file")"
  umask 077
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen > "$password_file"
  else
    python3 - "$password_file" <<'PY'
from pathlib import Path
import secrets
import sys
Path(sys.argv[1]).write_text(secrets.token_urlsafe(32) + "\n", encoding="utf-8")
PY
  fi
  chmod 600 "$password_file"
}

find_local_signing_identity_hash() {
  local keychain="$1"
  local identity_name="$2"
  security find-identity -v -p codesigning "$keychain" 2>/dev/null \
    | awk -v name="$identity_name" 'index($0, name) { print $2; exit }'
}

capture_user_keychain_list() {
  local output_file="$1"
  security list-keychains -d user > "$output_file"
}

restore_user_keychain_list() {
  local input_file="$1"
  if [[ ! -f "$input_file" ]]; then
    return 0
  fi
  python3 - "$input_file" <<'PY' | xargs security list-keychains -d user -s
from pathlib import Path
import sys
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    item = line.strip().strip('"')
    if item:
        print(item)
PY
}

prepend_user_keychain() {
  local input_file="$1"
  local keychain="$2"
  python3 - "$input_file" "$keychain" <<'PY' | xargs security list-keychains -d user -s
from pathlib import Path
import sys
items: list[str] = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    item = line.strip().strip('"')
    if item and item not in items:
        items.append(item)
keychain = sys.argv[2]
if keychain not in items:
    items.insert(0, keychain)
for item in items:
    print(item)
PY
}

create_local_signing_identity() {
  local keychain="$1"
  local keychain_password="$2"
  local identity_name="$3"
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/meeting-assistant-local-signing.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' RETURN

  if ! command -v openssl >/dev/null 2>&1; then
    echo "error: openssl is required to create the stable local signing identity" >&2
    exit 1
  fi

  cat > "$tmp_dir/openssl.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_codesign
[ dn ]
CN = $identity_name
O = Meeting Assistant Local
[ v3_codesign ]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmp_dir/key.pem" \
    -out "$tmp_dir/cert.pem" \
    -days 3650 \
    -config "$tmp_dir/openssl.cnf" >/dev/null 2>&1

  if ! openssl pkcs12 -legacy -export \
    -name "$identity_name" \
    -inkey "$tmp_dir/key.pem" \
    -in "$tmp_dir/cert.pem" \
    -out "$tmp_dir/identity.p12" \
    -passout "pass:$keychain_password" >/dev/null 2>&1; then
    openssl pkcs12 -export \
      -name "$identity_name" \
      -inkey "$tmp_dir/key.pem" \
      -in "$tmp_dir/cert.pem" \
      -out "$tmp_dir/identity.p12" \
      -passout "pass:$keychain_password" >/dev/null 2>&1
  fi

  security import "$tmp_dir/identity.p12" \
    -f pkcs12 \
    -k "$keychain" \
    -P "$keychain_password" \
    -T /usr/bin/codesign \
    -A >/dev/null
  security add-trusted-cert -r trustRoot -k "$keychain" "$tmp_dir/cert.pem" >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
  trap - RETURN
}

ensure_stable_local_signing_identity() {
  local keychain="$1"
  local password_file="$2"
  local identity_name="$3"
  local keychain_password

  if [[ -f "$keychain" && ! -f "$password_file" ]]; then
    echo "error: local signing keychain exists but password file is missing: $password_file" >&2
    echo "       set MA_NATIVE_LOCAL_APP_SIGNING_PASSWORD_FILE or remove the stale keychain." >&2
    exit 1
  fi
  if [[ ! -f "$password_file" ]]; then
    write_new_password_file "$password_file"
  fi
  keychain_password="$(password_file_value "$password_file")"
  if [[ -z "$keychain_password" ]]; then
    echo "error: local signing keychain password file is empty: $password_file" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$keychain")"
  if [[ ! -f "$keychain" ]]; then
    security create-keychain -p "$keychain_password" "$keychain" >/dev/null
  fi
  security unlock-keychain -p "$keychain_password" "$keychain" >/dev/null

  local identity_hash
  identity_hash="$(find_local_signing_identity_hash "$keychain" "$identity_name")"
  if [[ -z "$identity_hash" ]]; then
    create_local_signing_identity "$keychain" "$keychain_password" "$identity_name"
    identity_hash="$(find_local_signing_identity_hash "$keychain" "$identity_name")"
  fi
  if [[ -z "$identity_hash" ]]; then
    echo "error: unable to create or find local code-signing identity: $identity_name" >&2
    exit 1
  fi
  printf '%s\n' "$identity_hash"
}

codesign_installed_app() {
  local app="$1"
  local mode="$2"
  local keychain="$3"
  local identity_name="$4"
  local password_file="$5"
  local report_file="$6"
  mkdir -p "$(dirname "$report_file")"
  case "$mode" in
    stable-local)
      local identity_hash
      local old_keychain_list
      identity_hash="$(ensure_stable_local_signing_identity "$keychain" "$password_file" "$identity_name")"
      old_keychain_list="$(mktemp /tmp/meeting-assistant-keychains.XXXXXX)"
      capture_user_keychain_list "$old_keychain_list"
      prepend_user_keychain "$old_keychain_list" "$keychain"
      if ! /usr/bin/codesign --force --deep --keychain "$keychain" --sign "$identity_hash" "$app" >/dev/null; then
        restore_user_keychain_list "$old_keychain_list"
        rm -f "$old_keychain_list"
        echo "error: local stable codesign failed for $app" >&2
        exit 1
      fi
      restore_user_keychain_list "$old_keychain_list"
      rm -f "$old_keychain_list"
      {
        printf 'mode=%s\n' "$mode"
        printf 'identity_name=%s\n' "$identity_name"
        printf 'identity_hash=%s\n' "$identity_hash"
        printf 'keychain=%s\n' "$keychain"
      } > "$report_file"
      ;;
    ad-hoc | adhoc)
      /usr/bin/codesign --force --deep --sign - "$app" >/dev/null
      {
        printf 'mode=ad-hoc\n'
        printf 'identity_name=ad-hoc-local\n'
        printf 'identity_hash=\n'
        printf 'keychain=\n'
      } > "$report_file"
      ;;
    *)
      echo "error: MA_NATIVE_LOCAL_APP_SIGNING_MODE must be stable-local or ad-hoc, got: $mode" >&2
      exit 2
      ;;
  esac
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
      install_path="$install_dir/$install_app_name.app"
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
local_signing_keychain="$(resolve_path "$local_signing_keychain")"
local_signing_password_file="$(resolve_path "$local_signing_password_file")"
install_dir="$(dirname "$install_path")"
signing_metadata_file="$(dirname "$report_file")/local-app-install-signing.env"

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

require_source_app "$source_app"

if [[ -e "$install_path" ]]; then
  require_existing_install_target "$install_path"
fi

echo "MeetingAssistantNative local install:"
echo "  source: $source_app"
echo "  install: $install_path"
echo "  install bundle id: $install_bundle_id"
echo "  install bundle name: $install_bundle_name"
echo "  install display name: $install_display_name"
echo "  signing mode: $local_signing_mode"
if [[ "$local_signing_mode" == "stable-local" ]]; then
  echo "  local signing identity: $local_signing_identity_name"
  echo "  local signing keychain: $local_signing_keychain"
fi
echo "  report: $report_file"
echo "  distribution mode: local-direct"
echo "  modifies tcc or system settings: false"
echo "  requires developer id or notarization: false"

if is_truthy "$dry_run"; then
  echo "dry run: app not copied"
  exit 0
fi

mkdir -p "$install_dir"
tmp_app="$install_dir/.$install_bundle_name.app.install.$$"
rm -rf "$tmp_app"
trap 'rm -rf "$tmp_app"' EXIT INT TERM

/usr/bin/ditto "$source_app" "$tmp_app"
require_source_app "$tmp_app"
localize_installed_identity "$tmp_app"
require_installed_app "$tmp_app"
codesign_installed_app \
  "$tmp_app" \
  "$local_signing_mode" \
  "$local_signing_keychain" \
  "$local_signing_identity_name" \
  "$local_signing_password_file" \
  "$signing_metadata_file"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$tmp_app" >/dev/null

if [[ -e "$install_path" ]]; then
  rm -rf "$install_path"
fi
mv "$tmp_app" "$install_path"
trap - EXIT INT TERM

mkdir -p "$(dirname "$report_file")"
python3 - "$source_app" "$install_path" "$report_file" "$signing_metadata_file" <<'PY'
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
signing_metadata_file = Path(sys.argv[4])


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
    for key in ("Identifier", "Format", "CDHash", "Signature", "TeamIdentifier", "Authority"):
        match = re.search(rf"(?m)^{key}=(.+)$", output)
        if match:
            details[key] = match.group(1).strip()
    signature_size_match = re.search(r"(?m)^Signature size=(\d+)$", output)
    if signature_size_match and "Signature" not in details:
        details["Signature"] = "signed"
        details["SignatureSize"] = signature_size_match.group(1).strip()
    requirement = subprocess.run(
        ["/usr/bin/codesign", "-dr", "-", str(app)],
        text=True,
        capture_output=True,
        check=False,
    )
    requirement_output = requirement.stdout + requirement.stderr
    requirement_match = re.search(r"(?m)^designated => (.+)$", requirement_output)
    if requirement_match:
        details["DesignatedRequirement"] = requirement_match.group(1).strip()
    return details


def read_signing_metadata(path: Path) -> dict[str, str]:
    metadata: dict[str, str] = {}
    if not path.is_file():
        return metadata
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        metadata[key] = value
    return metadata


plist = info_plist(install_app)
source_plist = info_plist(source_app)
signing_metadata = read_signing_metadata(signing_metadata_file)
signing_mode = signing_metadata.get("mode", "unknown")
stable_signing = signing_mode == "stable-local"
report = {
    "report_schema": 1,
    "release_gate": "local-direct-app-install",
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "source_app": str(source_app),
    "source_app_identity": {
        "path": str(source_app),
        "CFBundleIdentifier": source_plist.get("CFBundleIdentifier", ""),
        "CFBundleName": source_plist.get("CFBundleName", ""),
        "CFBundleDisplayName": source_plist.get("CFBundleDisplayName", ""),
        "CFBundleShortVersionString": source_plist.get("CFBundleShortVersionString", ""),
        "codesign": codesign_details(source_app),
    },
    "installed_app": {
        "path": str(install_app),
        "CFBundleIdentifier": plist.get("CFBundleIdentifier", ""),
        "CFBundleName": plist.get("CFBundleName", ""),
        "CFBundleDisplayName": plist.get("CFBundleDisplayName", ""),
        "CFBundleShortVersionString": plist.get("CFBundleShortVersionString", ""),
        "codesign": codesign_details(install_app),
    },
    "local_signing": {
        "mode": signing_mode,
        "identity_name": signing_metadata.get("identity_name", ""),
        "identity_hash": signing_metadata.get("identity_hash", ""),
        "keychain": signing_metadata.get("keychain", ""),
        "stable_tcc_identity": stable_signing,
        "self_signed_local_identity": stable_signing,
    },
    "local_tcc_identity_strategy": (
        "The copied local app uses a distinct bundle id/name from Debug and XCUITest apps and, "
        "by default, a stable self-signed local code-signing identity so macOS Screen Recording "
        "authorization can bind to the bundle identifier plus certificate root and survive app "
        "content rebuilds. Ad-hoc signing is available only as an explicit diagnostic fallback "
        "and is not expected to preserve TCC grants across rebuilds."
    ),
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
