#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

derived_data_path="${MA_NATIVE_APP_DERIVED_DATA_PATH:-$component_dir/build/DerivedData/AppBundleUITests}"
destination="${MA_NATIVE_APP_XCODE_DESTINATION:-platform=macOS}"
real_capture_smoke="${MA_NATIVE_APP_REAL_CAPTURE_SMOKE:-0}"
real_capture_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled"
real_capture_log="$derived_data_path/real-capture-app-bundle-smoke.log"
real_processing_smoke="${MA_NATIVE_APP_REAL_PROCESSING_SMOKE:-0}"
real_processing_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealProcessingCLIProcessesNativeRecordingFromLaunchedAppBundleWhenExplicitlyEnabled"
real_processing_log="$derived_data_path/real-processing-app-bundle-smoke.log"
real_action_smoke="${MA_NATIVE_APP_REAL_ACTION_SMOKE:-0}"
real_action_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testRealProcessingCLITranscriptReviewExportAndDeleteFromLaunchedAppBundleWhenExplicitlyEnabled"
real_action_log="$derived_data_path/real-action-app-bundle-smoke.log"
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
mvp_full_stack_smoke="${MA_NATIVE_APP_MVP_FULL_STACK_SMOKE:-0}"
mvp_full_stack_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testMVPFullStackDesignedShellRecordingProcessingTranscriptActionsWhenExplicitlyEnabled"
mvp_full_stack_log="$derived_data_path/mvp-full-stack-app-bundle-smoke.log"

mkdir -p "$derived_data_path"

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

print_real_capture_permission_help() {
  local app_bundle_path="$1"

  cat >&2 <<EOF

native-app real capture app-bundle XCUITest failed with permission_denied.
This usually means macOS has not granted Screen Recording / Screen & System Audio Recording permission to the test app bundle.
DerivedData path: $derived_data_path
App bundle under test: ${app_bundle_path:-not found under DerivedData}
Captured xcodebuild log: $real_capture_log

To unblock this machine:
  1. Open System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording.
  2. Enable MeetingAssistantNative for the app bundle built under the DerivedData path above.
  3. Quit and relaunch the app if macOS asks, then rerun:
     MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh

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

if [[ "$real_capture_smoke" == "1" || "$real_capture_smoke" == "true" || "$real_capture_smoke" == "yes" ]]; then
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SMOKE" "1"

  app_bundle_path="$(find "$derived_data_path/Build/Products" -path "*/MeetingAssistantNative.app" -type d -print -quit)"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_capture_test" 2>&1 | tee "$real_capture_log"
  test_status=${PIPESTATUS[0]}
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real capture app-bundle XCUITest failed. Captured xcodebuild log: $real_capture_log" >&2
    if is_ui_testing_automation_blocked "$real_capture_log"; then
      print_ui_testing_automation_help "real capture" "$real_capture_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    if grep -q "permission_denied" "$real_capture_log"; then
      print_real_capture_permission_help "$app_bundle_path"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture app-bundle XCUITest passed."
  exit 0
fi

if [[ "$real_processing_smoke" == "1" || "$real_processing_smoke" == "true" || "$real_processing_smoke" == "yes" ]]; then
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_PROCESSING_SMOKE" "1"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_processing_test" 2>&1 | tee "$real_processing_log"
  test_status=${PIPESTATUS[0]}
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
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_ACTION_SMOKE" "1"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_action_test" 2>&1 | tee "$real_action_log"
  test_status=${PIPESTATUS[0]}
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

if [[ "$real_runtime_smoke" == "1" || "$real_runtime_smoke" == "true" || "$real_runtime_smoke" == "yes" ]]; then
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_RUNTIME_SMOKE" "1"
  rm -rf "$real_runtime_diagnostic_dir"
  mkdir -p "$real_runtime_diagnostic_dir"
  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_REAL_RUNTIME_DIAGNOSTIC_DIR" "$real_runtime_diagnostic_dir"
  require_env_for_real_runtime_smoke

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_runtime_test" 2>&1 | tee "$real_runtime_log"
  test_status=${PIPESTATUS[0]}
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
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_VSMA21_HARDENING_SMOKE" "1"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$vs_ma21_hardening_test" 2>&1 | tee "$vs_ma21_hardening_log"
  test_status=${PIPESTATUS[0]}
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
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE" "1"

  app_bundle_path="$(find "$derived_data_path/Build/Products" -path "*/MeetingAssistantNative.app" -type d -print -quit)"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_capture_same_chain_test" 2>&1 | tee "$real_capture_same_chain_log"
  test_status=${PIPESTATUS[0]}
  set -e

  if [[ "$test_status" -ne 0 ]]; then
    echo "native-app real capture same-chain app-bundle XCUITest failed. Captured xcodebuild log: $real_capture_same_chain_log" >&2
    if is_ui_testing_automation_blocked "$real_capture_same_chain_log"; then
      print_ui_testing_automation_help "real capture same-chain" "$real_capture_same_chain_log"
      print_ui_testing_automation_process_diagnostics
      print_ui_testing_automation_log_excerpt
    fi
    if grep -q "permission_denied" "$real_capture_same_chain_log"; then
      print_real_capture_permission_help "$app_bundle_path"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture same-chain app-bundle XCUITest passed."
  exit 0
fi

if [[ "$mvp_full_stack_smoke" == "1" || "$mvp_full_stack_smoke" == "true" || "$mvp_full_stack_smoke" == "yes" ]]; then
  xcodebuild build-for-testing \
    -project "$component_dir/MeetingAssistantNative.xcodeproj" \
    -scheme "MeetingAssistantNative" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO

  xctestrun_path="$(find "$derived_data_path/Build/Products" -maxdepth 1 -name "*.xctestrun" -print -quit)"
  if [[ -z "$xctestrun_path" ]]; then
    echo "error: build-for-testing did not produce an .xctestrun file under $derived_data_path/Build/Products" >&2
    exit 1
  fi

  set_xctestrun_env "$xctestrun_path" "MA_NATIVE_APP_MVP_FULL_STACK_SMOKE" "1"

  set +e
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$mvp_full_stack_test" 2>&1 | tee "$mvp_full_stack_log"
  test_status=${PIPESTATUS[0]}
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
