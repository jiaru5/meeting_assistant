#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

derived_data_path="${MA_NATIVE_APP_DERIVED_DATA_PATH:-$component_dir/build/DerivedData/AppBundleUITests}"
destination="${MA_NATIVE_APP_XCODE_DESTINATION:-platform=macOS}"
real_capture_smoke="${MA_NATIVE_APP_REAL_CAPTURE_SMOKE:-0}"
real_capture_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled"
real_capture_log="$derived_data_path/real-capture-app-bundle-smoke.log"

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
    if grep -q "permission_denied" "$real_capture_log"; then
      print_real_capture_permission_help "$app_bundle_path"
    fi
    exit "$test_status"
  fi

  echo "native-app real capture app-bundle XCUITest passed."
  exit 0
fi

xcodebuild test \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -parallel-testing-enabled NO

echo "native-app app-bundle XCUITest passed."
