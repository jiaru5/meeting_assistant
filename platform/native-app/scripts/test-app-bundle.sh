#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

derived_data_path="${MA_NATIVE_APP_DERIVED_DATA_PATH:-$component_dir/build/DerivedData/AppBundleUITests}"
destination="${MA_NATIVE_APP_XCODE_DESTINATION:-platform=macOS}"
real_capture_smoke="${MA_NATIVE_APP_REAL_CAPTURE_SMOKE:-0}"
real_capture_test="MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled"

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

  xcodebuild test-without-building \
    -xctestrun "$xctestrun_path" \
    -destination "$destination" \
    "-only-testing:$real_capture_test"

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
