#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

derived_data_path="${MA_NATIVE_APP_DERIVED_DATA_PATH:-$component_dir/build/DerivedData/AppBundleUITests}"
destination="${MA_NATIVE_APP_XCODE_DESTINATION:-platform=macOS}"
reuse_xctestrun="${MA_NATIVE_APP_REUSE_XCTESTRUN:-auto}"
xctestrun_fingerprint_path="$derived_data_path/.meeting-assistant-xctestrun-inputs.sha256"
ui_automation_retry_attempts="${MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS:-1}"
ui_automation_retry_delay_seconds="${MA_NATIVE_APP_UI_AUTOMATION_RETRY_DELAY_SECONDS:-5}"
real_capture_smoke="${MA_NATIVE_APP_REAL_CAPTURE_SMOKE:-0}"
real_capture_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled"
real_capture_log="$derived_data_path/real-capture-app-bundle-smoke.log"
real_processing_smoke="${MA_NATIVE_APP_REAL_PROCESSING_SMOKE:-0}"
real_processing_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealProcessingCLIProcessesNativeRecordingFromLaunchedAppBundleWhenExplicitlyEnabled"
real_processing_log="$derived_data_path/real-processing-app-bundle-smoke.log"
real_action_smoke="${MA_NATIVE_APP_REAL_ACTION_SMOKE:-0}"
real_action_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealProcessingCLITranscriptReviewExportAndDeleteFromLaunchedAppBundleWhenExplicitlyEnabled"
real_action_log="$derived_data_path/real-action-app-bundle-smoke.log"
real_action_os_smoke="${MA_NATIVE_APP_REAL_ACTION_OS_SMOKE:-0}"
real_action_os_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealProcessingCLISystemClipboardSavePanelExportAndDeleteFromLaunchedAppBundleWhenExplicitlyEnabled"
real_action_os_log="$derived_data_path/real-action-os-app-bundle-smoke.log"
real_runtime_smoke="${MA_NATIVE_APP_REAL_RUNTIME_SMOKE:-0}"
real_runtime_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealWhisperRuntimeTranscriptReviewFromLaunchedAppBundleWhenExplicitlyEnabled"
real_runtime_log="$derived_data_path/real-runtime-app-bundle-smoke.log"
real_runtime_ui_automation_report="$derived_data_path/reports/ui-automation/real-runtime-ui-automation-report.json"
real_runtime_diagnostic_dir="$derived_data_path/reports/real-runtime-diagnostics"
vs_ma21_hardening_smoke="${MA_NATIVE_APP_VSMA21_HARDENING_SMOKE:-0}"
vs_ma21_hardening_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testVSMA21AppBundleProcessingPathConflictRetryPreservesOriginalCaptureArtifactWhenExplicitlyEnabled"
vs_ma21_hardening_log="$derived_data_path/vs-ma-21-hardening-app-bundle-smoke.log"
vs_ma21_hardening_ui_automation_report="$derived_data_path/reports/ui-automation/vs-ma-21-hardening-ui-automation-report.json"
real_capture_same_chain_smoke="${MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE:-0}"
real_capture_same_chain_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testVSMA21RealScreenCaptureKitProcessingTranscriptActionsSameChainWhenExplicitlyEnabled"
real_capture_same_chain_log="$derived_data_path/real-capture-same-chain-app-bundle-smoke.log"
real_capture_real_runtime_same_chain_smoke="${MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE:-0}"
real_capture_real_runtime_same_chain_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testVSMA23RealScreenCaptureKitWhisperRuntimeTranscriptActionsSameChainWhenExplicitlyEnabled"
real_capture_real_runtime_same_chain_log="$derived_data_path/real-capture-real-runtime-same-chain-app-bundle-smoke.log"
mvp_full_stack_smoke="${MA_NATIVE_APP_MVP_FULL_STACK_SMOKE:-0}"
mvp_full_stack_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testMVPFullStackDesignedShellRecordingProcessingTranscriptActionsWhenExplicitlyEnabled"
mvp_full_stack_log="$derived_data_path/mvp-full-stack-app-bundle-smoke.log"

mkdir -p "$derived_data_path"

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

find_xctestrun_path() {
  find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit 2>/dev/null || true
}

compute_xctestrun_input_fingerprint() {
  local root_dir
  local relative_path

  root_dir="$(cd "$component_dir/../.." && pwd)"
  if ! command -v git >/dev/null 2>&1 || ! command -v shasum >/dev/null 2>&1; then
    return 1
  fi

  (
    printf 'destination=%s\n' "$destination"
    xcodebuild -version 2>/dev/null | sed 's/^/xcodebuild=/' || true
    git -C "$root_dir" ls-files -z -- \
      "platform/native-app/App" \
      "platform/native-app/Sources" \
      "platform/native-app/UITests" \
      "platform/native-app/MeetingAssistantNative.xcodeproj/project.pbxproj" \
      "platform/native-app/MeetingAssistantNative.xcodeproj/xcshareddata" \
      | while IFS= read -r -d '' relative_path; do
          printf 'path=%s\n' "$relative_path"
          shasum -a 256 "$root_dir/$relative_path"
        done
  ) | shasum -a 256 | awk '{print $1}'
}

prepare_xctestrun() {
  local smoke_name="$1"
  local current_fingerprint=""
  local saved_fingerprint=""

  xctestrun_path="$(find_xctestrun_path)"
  current_fingerprint="$(compute_xctestrun_input_fingerprint || true)"

  if [[ "$reuse_xctestrun" == "auto" ]]; then
    if [[ -n "$xctestrun_path" && -n "$current_fingerprint" && -f "$xctestrun_fingerprint_path" ]]; then
      saved_fingerprint="$(<"$xctestrun_fingerprint_path")"
      if [[ "$saved_fingerprint" == "$current_fingerprint" ]]; then
        echo "native-app $smoke_name app-bundle XCUITest auto-reusing existing xctestrun: $xctestrun_path" >&2
        echo "Set MA_NATIVE_APP_REUSE_XCTESTRUN=0 to force rebuild-for-testing." >&2
        return 0
      fi
      echo "native-app $smoke_name app-bundle XCUITest inputs changed; rebuilding xctestrun for current app/test sources." >&2
    elif [[ -n "$xctestrun_path" ]]; then
      echo "native-app $smoke_name app-bundle XCUITest cannot prove existing xctestrun fingerprint; rebuilding once and recording a reuse fingerprint." >&2
    fi
  elif is_truthy "$reuse_xctestrun"; then
    if [[ -z "$xctestrun_path" ]]; then
      echo "error: MA_NATIVE_APP_REUSE_XCTESTRUN=1 was set but no .xctestrun file exists under $derived_data_path/Build/Products" >&2
      echo "Run the same app-bundle smoke once without MA_NATIVE_APP_REUSE_XCTESTRUN before granting or reusing the exact app bundle." >&2
      exit 1
    fi
    if [[ -n "$current_fingerprint" && -f "$xctestrun_fingerprint_path" ]]; then
      saved_fingerprint="$(<"$xctestrun_fingerprint_path")"
      if [[ "$saved_fingerprint" != "$current_fingerprint" ]]; then
        echo "warning: MA_NATIVE_APP_REUSE_XCTESTRUN=1 is reusing an xctestrun whose app/test input fingerprint differs from the current checkout." >&2
      fi
    fi
    echo "native-app $smoke_name app-bundle XCUITest reusing existing xctestrun: $xctestrun_path" >&2
    return 0
  elif [[ "$reuse_xctestrun" != "0" && "$reuse_xctestrun" != "false" && "$reuse_xctestrun" != "FALSE" && "$reuse_xctestrun" != "no" && "$reuse_xctestrun" != "NO" ]]; then
    echo "error: MA_NATIVE_APP_REUSE_XCTESTRUN must be auto, 0, 1, true, false, yes, or no." >&2
    exit 2
  fi

  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find_xctestrun_path)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi
  if [[ -n "$current_fingerprint" ]]; then
    printf '%s\n' "$current_fingerprint" >"$xctestrun_fingerprint_path"
  fi
}

set_xctestrun_env() {
  local xctestrun_path="$1"
  local key="$2"
  local value="$3"
  local plist_path

  for plist_path in \
    ":MeetingAssistantNativeAppUITests:EnvironmentVariables:$key" \
    ":MeetingAssistantNativeAppUITests:TestingEnvironmentVariables:$key"
  do
    /usr/libexec/PlistBuddy -c "Set $plist_path $value" "$xctestrun_path" >/dev/null 2>&1 \
      || /usr/libexec/PlistBuddy -c "Add $plist_path string $value" "$xctestrun_path" >/dev/null
  done
}

reset_xctestrun_smoke_env() {
  local key

  for key in \
    MA_NATIVE_APP_REAL_CAPTURE_SMOKE \
    MA_NATIVE_APP_REAL_PROCESSING_SMOKE \
    MA_NATIVE_APP_REAL_ACTION_SMOKE \
    MA_NATIVE_APP_REAL_ACTION_OS_SMOKE \
    MA_NATIVE_APP_REAL_RUNTIME_SMOKE \
    MA_NATIVE_APP_VSMA21_HARDENING_SMOKE \
    MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE \
    MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE \
    MA_NATIVE_APP_MVP_FULL_STACK_SMOKE
  do
    set_xctestrun_env "$xctestrun_path" "$key" "0"
  done
}

print_app_bundle_identity_diagnostics() {
  local app_bundle_path="$1"
  local info_plist
  local bundle_id=""
  local codesign_details=""
  local designated_requirement=""
  local signature=""
  local team_identifier=""
  local cdhash=""
  local spctl_assessment=""

  if [[ -z "$app_bundle_path" || ! -d "$app_bundle_path" ]]; then
    return 0
  fi

  info_plist="$app_bundle_path/Contents/Info.plist"
  if [[ -f "$info_plist" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist" 2>/dev/null || true)"
  fi
  codesign_details="$(codesign -dv "$app_bundle_path" 2>&1 || true)"
  designated_requirement="$(codesign -dr - "$app_bundle_path" 2>&1 | grep -m 1 "designated =>" || true)"
  signature="$(printf '%s\n' "$codesign_details" | sed -n 's/^Signature=//p' | head -n 1)"
  team_identifier="$(printf '%s\n' "$codesign_details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
  cdhash="$(printf '%s\n' "$designated_requirement" | sed -n 's/.*cdhash H"\([^"]*\)".*/\1/p' | head -n 1)"
  spctl_assessment="$(spctl -a -vv -t exec "$app_bundle_path" 2>&1 | head -n 1 || true)"

  {
    echo "App bundle identifier: ${bundle_id:-unknown}"
    echo "App bundle signature: ${signature:-unknown}"
    echo "App bundle team identifier: ${team_identifier:-unknown}"
    echo "App bundle cdhash: ${cdhash:-unknown}"
    echo "App bundle designated requirement: ${designated_requirement:-unknown}"
    echo "App bundle spctl assessment: ${spctl_assessment:-unknown}"
  } >&2
}

find_app_bundle_under_test() {
  find "$derived_data_path/Build/Products" -path "*/MeetingAssistantNative.app" -type d -print -quit 2>/dev/null || true
}

collect_matching_app_bundle_paths() {
  local app_bundle_path="$1"
  local info_plist
  local bundle_id=""

  info_plist="$app_bundle_path/Contents/Info.plist"
  if [[ -f "$info_plist" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist" 2>/dev/null || true)"
  fi
  if [[ -z "$bundle_id" ]]; then
    return 0
  fi

  python3 - "$bundle_id" "$app_bundle_path" "$component_dir" <<'PY'
import os
import plistlib
import sys

bundle_id, app_bundle_path, component_dir = sys.argv[1:4]
component_dir = os.path.realpath(component_dir)
repo_root = os.path.realpath(os.path.join(component_dir, "../.."))
develop_root = os.path.realpath(os.path.join(repo_root, ".."))
roots = [
    os.path.join(component_dir, "build", "DerivedData"),
    os.path.expanduser("~/Library/Developer/Xcode/DerivedData"),
]

try:
    for name in os.listdir(develop_root):
        if name == "meeting_assistant" or name.startswith("meeting_assistant-"):
            roots.append(os.path.join(develop_root, name, "platform", "native-app", "build", "DerivedData"))
except OSError:
    pass

matches = {os.path.realpath(app_bundle_path)}
for root in roots:
    if not os.path.isdir(root):
        continue
    for dirpath, dirnames, _filenames in os.walk(root):
        dirnames[:] = [
            name for name in dirnames
            if name not in {".git", ".build", "node_modules", "ModuleCache.noindex", "SDKStatCaches.noindex"}
        ]
        if "MeetingAssistantNative.app" not in dirnames:
            continue
        candidate = os.path.realpath(os.path.join(dirpath, "MeetingAssistantNative.app"))
        plist_path = os.path.join(candidate, "Contents", "Info.plist")
        try:
            with open(plist_path, "rb") as handle:
                plist = plistlib.load(handle)
        except Exception:
            continue
        if plist.get("CFBundleIdentifier") == bundle_id:
            matches.add(candidate)

for match in sorted(matches):
    print(match)
PY
}

print_app_bundle_tcc_identity_diagnostics() {
  local app_bundle_path="$1"
  local smoke_name="$2"
  local codesign_details=""
  local designated_requirement=""
  local signature=""
  local team_identifier=""
  local cdhash=""
  local matching_paths=""
  local other_paths=""
  local other_count="0"

  if [[ -z "$app_bundle_path" || ! -d "$app_bundle_path" ]]; then
    return 0
  fi

  codesign_details="$(codesign -dv "$app_bundle_path" 2>&1 || true)"
  designated_requirement="$(codesign -dr - "$app_bundle_path" 2>&1 | grep -m 1 "designated =>" || true)"
  signature="$(printf '%s\n' "$codesign_details" | sed -n 's/^Signature=//p' | head -n 1)"
  team_identifier="$(printf '%s\n' "$codesign_details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
  cdhash="$(printf '%s\n' "$designated_requirement" | sed -n 's/.*cdhash H"\([^"]*\)".*/\1/p' | head -n 1)"
  matching_paths="$(collect_matching_app_bundle_paths "$app_bundle_path" || true)"
  other_paths="$(printf '%s\n' "$matching_paths" | grep -F -x -v "$(cd "$(dirname "$app_bundle_path")" && pwd -P)/$(basename "$app_bundle_path")" | sed '/^$/d' || true)"
  other_count="$(printf '%s\n' "$other_paths" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$signature" != "adhoc" && -n "$team_identifier" && "$team_identifier" != "not set" && "$other_count" == "0" ]]; then
    return 0
  fi

  {
    echo
    echo "TCC/app bundle identity diagnostic for ${smoke_name} app-bundle XCUITest:"
    echo " - app bundle under test: $app_bundle_path"
    echo " - signature: ${signature:-unknown}"
    echo " - team identifier: ${team_identifier:-unknown}"
    echo " - cdhash: ${cdhash:-unknown}"
    if [[ "$signature" == "adhoc" || -z "$team_identifier" || "$team_identifier" == "not set" ]]; then
      echo " - current Debug app bundle is not signed with a stable Apple team identity; macOS Screen Recording TCC can bind the grant to this build's path/cdhash, so rebuilding may require a new grant even when System Settings shows another MeetingAssistantNative row."
      echo " - for same-bundle reruns, prefer MA_NATIVE_APP_REUSE_XCTESTRUN=1; for durable cross-machine evidence, use a stable Apple Development or Developer ID signing identity."
    fi
    if [[ "$other_count" != "0" ]]; then
      echo " - other MeetingAssistantNative.app bundles with the same CFBundleIdentifier were found; System Settings can show the same app name while the grant belongs to a different path:"
      printf '%s\n' "$other_paths" | sed 's/^/   * /'
    fi
    echo " - set MA_NATIVE_APP_TCC_IDENTITY_DIAGNOSTICS=0 to suppress this diagnostic."
  } >&2
}

terminate_stale_meeting_assistant_instances() {
  local app_bundle_path="$1"
  local smoke_name="$2"
  local expected_executable

  if ! is_truthy "${MA_NATIVE_APP_TERMINATE_STALE_INSTANCES:-1}"; then
    return 0
  fi
  if [[ -z "$app_bundle_path" || ! -d "$app_bundle_path" ]]; then
    return 0
  fi

  expected_executable="$app_bundle_path/Contents/MacOS/MeetingAssistantNative"
  if [[ ! -x "$expected_executable" ]]; then
    return 0
  fi

  python3 - "$expected_executable" "$smoke_name" <<'PY'
import os
import signal
import subprocess
import sys
import time

expected_executable = os.path.realpath(sys.argv[1])
smoke_name = sys.argv[2]
executable_suffix = "/MeetingAssistantNative.app/Contents/MacOS/MeetingAssistantNative"

try:
    process_table = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
except Exception as error:
    print(
        f"warning: could not inspect MeetingAssistantNative processes before {smoke_name} app-bundle XCUITest: {error}",
        file=sys.stderr,
    )
    sys.exit(0)

stale_processes = []
for line in process_table.splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    parts = stripped.split(None, 1)
    if len(parts) != 2:
        continue
    pid_text, command = parts
    suffix_index = command.find(executable_suffix)
    if suffix_index < 0:
        continue
    executable = command[: suffix_index + len(executable_suffix)]
    if os.path.realpath(executable) == expected_executable:
        continue
    try:
        pid = int(pid_text)
    except ValueError:
        continue
    stale_processes.append((pid, executable))

for pid, executable in stale_processes:
    print(
        f"native-app {smoke_name} app-bundle XCUITest terminating stale MeetingAssistantNative instance pid={pid}: {executable}",
        file=sys.stderr,
    )
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        continue
    except PermissionError as error:
        print(
            f"warning: could not terminate stale MeetingAssistantNative instance pid={pid}: {error}",
            file=sys.stderr,
        )

deadline = time.time() + 2.0
remaining = {pid for pid, _ in stale_processes}
while remaining and time.time() < deadline:
    for pid in list(remaining):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            remaining.remove(pid)
        except PermissionError:
            remaining.remove(pid)
    if remaining:
        time.sleep(0.1)

for pid in remaining:
    try:
        os.kill(pid, signal.SIGKILL)
        print(
            f"native-app {smoke_name} app-bundle XCUITest force-terminated stale MeetingAssistantNative instance pid={pid}",
            file=sys.stderr,
        )
    except ProcessLookupError:
        pass
    except PermissionError as error:
        print(
            f"warning: could not force-terminate stale MeetingAssistantNative instance pid={pid}: {error}",
            file=sys.stderr,
        )
PY
}

print_real_capture_permission_help() {
  local app_bundle_path="$1"
  local log_path="${2:-$real_capture_log}"
  local rerun_command="${3:-MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh}"

  cat >&2 <<EOF

native-app real capture app-bundle XCUITest failed with permission_denied.
This usually means macOS has not granted Screen Recording / Screen & System Audio Recording permission to the test app bundle.
DerivedData path: $derived_data_path
App bundle under test: ${app_bundle_path:-not found under DerivedData}
Captured xcodebuild log: $log_path

Current app bundle identity:
EOF

  print_app_bundle_identity_diagnostics "$app_bundle_path"

  cat >&2 <<EOF

To unblock this machine:
  1. Open System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording.
  2. Enable MeetingAssistantNative for the exact app bundle path and identity printed above.
  3. Quit and relaunch the app if macOS asks, then rerun:
     $rerun_command
  4. If you granted the exact app bundle above and have not rebuilt since then, rerun without changing the app signature:
     MA_NATIVE_APP_REUSE_XCTESTRUN=1 $rerun_command

Optional settings shortcut:
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
EOF
}

print_ui_testing_automation_help() {
  local smoke_name="$1"
  local log_path="$2"

  cat >&2 <<EOF

native-app ${smoke_name} app-bundle XCUITest was blocked before the test body by macOS UI automation setup.
The runner reported LocalAuthentication or Automation Mode initialization failure, so this run cannot prove UI or provider behavior.
Captured xcodebuild log: $log_path

To unblock this machine:
  1. Resolve or dismiss any pending macOS loginwindow / Touch ID / password authentication prompt.
  2. Keep the display awake and unlocked before starting the app-bundle smoke.
  3. Check System Settings > Privacy & Security > Accessibility / Developer Tools for Xcode and the UI test runner if macOS prompts for automation control.
  4. Rerun the same command after Automation Mode can be enabled without another LocalAuthentication request or timeout.
EOF
}

print_ui_testing_automation_log_excerpt() {
  local output

  if ! command -v /usr/bin/log >/dev/null 2>&1; then
    return 0
  fi

  output="$(
    /usr/bin/log show \
      --style compact \
      --last 3m \
      --predicate 'process == "testmanagerd" OR process == "loginwindow" OR process == "coreauthd" OR process == "MeetingAssistantNativeAppUITests-Runner" OR eventMessage CONTAINS[c] "Failed to enable Automation Mode" OR eventMessage CONTAINS[c] "Timed out while enabling automation mode" OR eventMessage CONTAINS[c] "System authentication is running"' \
      2>/dev/null \
      | grep -Ei 'Failed to enable Automation Mode|Timed out while enabling automation mode|System authentication is running|loginwindow.*CoreAuthentication|remoteAuthenticationInProgress|MeetingAssistantNativeAppUITests-Runner|testmanagerd' \
      | tail -n 40
  )" || true

  if [[ -n "$output" ]]; then
    {
      echo
      echo "UI automation diagnostic excerpt:"
      echo "$output"
    } >&2
  fi
}

print_ui_testing_automation_process_diagnostics() {
  local processes
  local launchctl_state

  processes="$(
    ps -axo pid,ppid,stat,etime,command \
      | grep -Ei 'testmanagerd|MeetingAssistantNative|AppUITests|xcodebuild|loginwindow|SecurityAgent|LocalAuthentication|coreauth|universalAccessAuthWarn|online-auth-agent' \
      | grep -Ev 'grep -Ei|test-app-bundle\.sh' \
      | tail -n 80
  )" || true

  if [[ -n "$processes" ]]; then
    {
      echo
      echo "UI automation process diagnostics:"
      echo "$processes"
    } >&2
  fi

  if command -v launchctl >/dev/null 2>&1; then
    launchctl_state="$(
      launchctl print "gui/$(id -u)/com.apple.testmanagerd" 2>/dev/null \
        | grep -E 'state =|active count =|pid =|runs =|last terminating signal' \
        | head -n 20
    )" || true

    if [[ -n "$launchctl_state" ]]; then
      {
        echo
        echo "testmanagerd launchctl diagnostics:"
        echo "$launchctl_state"
      } >&2
    fi
  fi
}

is_ui_testing_automation_blocked() {
  local log_path="$1"

  grep -Eqi 'LocalAuthentication|System authentication is running|Timed out while enabling automation mode|Failed to initialize for UI testing|Failed to enable Automation Mode' "$log_path"
}

run_app_bundle_test_without_building() {
  local smoke_name="$1"
  local log_path="$2"
  local test_identifier="$3"
  local app_bundle_path
  local attempt=1
  local max_attempts
  local attempt_log
  local test_status

  if ! [[ "$ui_automation_retry_attempts" =~ ^[0-9]+$ ]]; then
    echo "error: MA_NATIVE_APP_UI_AUTOMATION_RETRY_ATTEMPTS must be a non-negative integer" >&2
    return 2
  fi
  max_attempts=$((ui_automation_retry_attempts + 1))

  app_bundle_path="$(find_app_bundle_under_test)"
  terminate_stale_meeting_assistant_instances "$app_bundle_path" "$smoke_name"
  if is_truthy "${MA_NATIVE_APP_TCC_IDENTITY_DIAGNOSTICS:-1}"; then
    print_app_bundle_tcc_identity_diagnostics "$app_bundle_path" "$smoke_name"
  fi

  : > "$log_path"

  while [[ "$attempt" -le "$max_attempts" ]]; do
    attempt_log="$log_path.attempt-$attempt.tmp"
    {
      echo "== native-app $smoke_name app-bundle XCUITest attempt $attempt/$max_attempts =="
    } >>"$log_path"

    set +e
    xcodebuild test-without-building \
      -xctestrun "$xctestrun_path" \
      -destination "$destination" \
      "-only-testing:$test_identifier" 2>&1 | tee "$attempt_log"
    test_status=${PIPESTATUS[0]}
    set +e

    cat "$attempt_log" >>"$log_path"

    if [[ "$test_status" -eq 0 ]]; then
      rm -f "$attempt_log"
      return 0
    fi

    if ! is_ui_testing_automation_blocked "$attempt_log"; then
      rm -f "$attempt_log"
      return "$test_status"
    fi

    rm -f "$attempt_log"

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      return "$test_status"
    fi

    echo "native-app $smoke_name app-bundle XCUITest was blocked before the test body; retrying after ${ui_automation_retry_delay_seconds}s ($attempt/$ui_automation_retry_attempts retries used)." >&2
    sleep "$ui_automation_retry_delay_seconds"
    attempt=$((attempt + 1))
  done
}

write_ui_testing_automation_blocker_report() {
  local smoke_name="$1"
  local log_path="$2"
  local report_path="$3"
  local exit_code="$4"
  local root_dir

  root_dir="$(cd "$component_dir/../.." && pwd)"
  python3 "$root_dir/platform/e2e/native_app_bundle_ui_automation_report.py" \
    --smoke-name "$smoke_name" \
    --log "$log_path" \
    --report "$report_path" \
    --exit-code "$exit_code" \
    --destination "$destination" >&2 || true
}

require_env_for_real_runtime_smoke() {
  local name

  for name in \
    MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME \
    MEETING_ASSISTANT_TRANSCRIPTION_MODEL \
    MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO
  do
    if [[ -z "${!name:-}" ]]; then
      echo "native-app real runtime app-bundle XCUITest requires $name to be configured." >&2
      exit 1
    fi
    set_xctestrun_env "$xctestrun_path" "$name" "${!name}"
  done
}

configure_host_ffmpeg_for_app_bundle() {
  local ffmpeg_path="${MEETING_ASSISTANT_FFMPEG_PATH:-}"

  if [[ -z "$ffmpeg_path" ]]; then
    ffmpeg_path="$(command -v ffmpeg || true)"
  fi

  if [[ -n "$ffmpeg_path" ]]; then
    set_xctestrun_env "$xctestrun_path" "MEETING_ASSISTANT_FFMPEG_PATH" "$ffmpeg_path"
  fi
}

if [[ "$real_capture_smoke" == "1" || "$real_capture_smoke" == "true" || "$real_capture_smoke" == "yes" ]]; then
  prepare_xctestrun "real capture"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SMOKE" "1"

  app_bundle_path="$(find_app_bundle_under_test)"

  set +e
  run_app_bundle_test_without_building "real capture" "$real_capture_log" "$real_capture_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real capture app-bundle XCUITest failed. Captured xcodebuild log: $real_capture_log" >&2
    if is_ui_testing_automation_blocked "$real_capture_log"; then
      print_ui_testing_automation_help "real capture" "$real_capture_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    if grep -q "permission_denied" "$real_capture_log"; then
      print_real_capture_permission_help \
        "$app_bundle_path" \
        "$real_capture_log" \
        "MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_processing_smoke" == "1" || "$real_processing_smoke" == "true" || "$real_processing_smoke" == "yes" ]]; then
  prepare_xctestrun "real processing"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_PROCESSING_SMOKE" "1"

  set +e
  run_app_bundle_test_without_building "real processing" "$real_processing_log" "$real_processing_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real processing app-bundle XCUITest failed. Captured xcodebuild log: $real_processing_log" >&2
    if is_ui_testing_automation_blocked "$real_processing_log"; then
      print_ui_testing_automation_help "real processing" "$real_processing_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app real processing app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_action_smoke" == "1" || "$real_action_smoke" == "true" || "$real_action_smoke" == "yes" ]]; then
  prepare_xctestrun "real action"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_ACTION_SMOKE" "1"

  set +e
  run_app_bundle_test_without_building "real action" "$real_action_log" "$real_action_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real action app-bundle XCUITest failed. Captured xcodebuild log: $real_action_log" >&2
    if is_ui_testing_automation_blocked "$real_action_log"; then
      print_ui_testing_automation_help "real action" "$real_action_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app real action app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_action_os_smoke" == "1" || "$real_action_os_smoke" == "true" || "$real_action_os_smoke" == "yes" ]]; then
  prepare_xctestrun "real action OS"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_ACTION_OS_SMOKE" "1"

  set +e
  run_app_bundle_test_without_building "real action OS" "$real_action_os_log" "$real_action_os_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real action OS app-bundle XCUITest failed. Captured xcodebuild log: $real_action_os_log" >&2
    if is_ui_testing_automation_blocked "$real_action_os_log"; then
      print_ui_testing_automation_help "real action OS" "$real_action_os_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app real action OS app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_runtime_smoke" == "1" || "$real_runtime_smoke" == "true" || "$real_runtime_smoke" == "yes" ]]; then
  prepare_xctestrun "real runtime"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_RUNTIME_SMOKE" "1"
  rm -rf "$real_runtime_diagnostic_dir"
  mkdir -p "$real_runtime_diagnostic_dir"
  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_REAL_RUNTIME_DIAGNOSTIC_DIR" "$real_runtime_diagnostic_dir"
  require_env_for_real_runtime_smoke

  set +e
  run_app_bundle_test_without_building "real runtime" "$real_runtime_log" "$real_runtime_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real runtime app-bundle XCUITest failed. Captured xcodebuild log: $real_runtime_log" >&2
    echo "native-app real runtime diagnostics directory: $real_runtime_diagnostic_dir" >&2
    write_ui_testing_automation_blocker_report "real runtime" "$real_runtime_log" "$real_runtime_ui_automation_report" "$test_status"
    if is_ui_testing_automation_blocked "$real_runtime_log"; then
      print_ui_testing_automation_help "real runtime" "$real_runtime_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app real runtime app-bundle XCUITest passed."
  exit 0
fi

if [[ "$vs_ma21_hardening_smoke" == "1" || "$vs_ma21_hardening_smoke" == "true" || "$vs_ma21_hardening_smoke" == "yes" ]]; then
  prepare_xctestrun "VS-MA-21 hardening"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_VSMA21_HARDENING_SMOKE" "1"

  set +e
  run_app_bundle_test_without_building "VS-MA-21 hardening" "$vs_ma21_hardening_log" "$vs_ma21_hardening_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app VS-MA-21 hardening app-bundle XCUITest failed. Captured xcodebuild log: $vs_ma21_hardening_log" >&2
    write_ui_testing_automation_blocker_report "VS-MA-21 hardening" "$vs_ma21_hardening_log" "$vs_ma21_hardening_ui_automation_report" "$test_status"
    if is_ui_testing_automation_blocked "$vs_ma21_hardening_log"; then
      print_ui_testing_automation_help "VS-MA-21 hardening" "$vs_ma21_hardening_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app VS-MA-21 hardening app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_capture_same_chain_smoke" == "1" || "$real_capture_same_chain_smoke" == "true" || "$real_capture_same_chain_smoke" == "yes" ]]; then
  prepare_xctestrun "real capture same-chain"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" "1"
  configure_host_ffmpeg_for_app_bundle

  app_bundle_path="$(find "$derived_data_path/Build/Products" -path "*/MeetingAssistantNative.app" -type d -print -quit)"

  set +e
  run_app_bundle_test_without_building "real capture same-chain" "$real_capture_same_chain_log" "$real_capture_same_chain_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real capture same-chain app-bundle XCUITest failed. Captured xcodebuild log: $real_capture_same_chain_log" >&2
    if is_ui_testing_automation_blocked "$real_capture_same_chain_log"; then
      print_ui_testing_automation_help "real capture same-chain" "$real_capture_same_chain_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    if grep -q "permission_denied" "$real_capture_same_chain_log"; then
      print_real_capture_permission_help \
        "$app_bundle_path" \
        "$real_capture_same_chain_log" \
        "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture same-chain app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_capture_real_runtime_same_chain_smoke" == "1" || "$real_capture_real_runtime_same_chain_smoke" == "true" || "$real_capture_real_runtime_same_chain_smoke" == "yes" ]]; then
  prepare_xctestrun "real capture real-runtime same-chain"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE" "1"
  configure_host_ffmpeg_for_app_bundle
  require_env_for_real_runtime_smoke

  app_bundle_path="$(find "$derived_data_path/Build/Products" -path "*/MeetingAssistantNative.app" -type d -print -quit)"

  set +e
  run_app_bundle_test_without_building "real capture real-runtime same-chain" "$real_capture_real_runtime_same_chain_log" "$real_capture_real_runtime_same_chain_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real capture real-runtime same-chain app-bundle XCUITest failed. Captured xcodebuild log: $real_capture_real_runtime_same_chain_log" >&2
    if is_ui_testing_automation_blocked "$real_capture_real_runtime_same_chain_log"; then
      print_ui_testing_automation_help "real capture real-runtime same-chain" "$real_capture_real_runtime_same_chain_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    if grep -q "permission_denied" "$real_capture_real_runtime_same_chain_log"; then
      print_real_capture_permission_help \
        "$app_bundle_path" \
        "$real_capture_real_runtime_same_chain_log" \
        "MA_NATIVE_APP_REAL_CAPTURE_REAL_RUNTIME_SAME_CHAIN_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture real-runtime same-chain app-bundle XCUITest passed."
  exit 0
fi

if [[ "$mvp_full_stack_smoke" == "1" || "$mvp_full_stack_smoke" == "true" || "$mvp_full_stack_smoke" == "yes" ]]; then
  prepare_xctestrun "MVP full-stack"
  reset_xctestrun_smoke_env

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" "1"

  set +e
  run_app_bundle_test_without_building "MVP full-stack" "$mvp_full_stack_log" "$mvp_full_stack_test"
  test_status=$?
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app MVP full-stack app-bundle XCUITest failed. Captured xcodebuild log: $mvp_full_stack_log" >&2
    if is_ui_testing_automation_blocked "$mvp_full_stack_log"; then
      print_ui_testing_automation_help "MVP full-stack" "$mvp_full_stack_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    exit "$test_status"
  fi

  echo "native-app MVP full-stack app-bundle XCUITest passed."
  exit 0
fi

xcodebuild test \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -parallel-testing-enabled NO

echo "native-app app-bundle XCUITest passed."
