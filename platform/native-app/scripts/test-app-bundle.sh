#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

derived_data_path="${MA_NATIVE_APP_DERIVED_DATA_PATH:-$component_dir/build/DerivedData/AppBundleUITests}"
destination="${MA_NATIVE_APP_XCODE_DESTINATION:-platform=macOS}"

mkdir -p "$derived_data_path"

xcodebuild test \
  -project "$component_dir/MeetingAssistantNative.xcodeproj" \
  -scheme "MeetingAssistantNative" \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -parallel-testing-enabled NO

echo "native-app app-bundle XCUITest passed."
