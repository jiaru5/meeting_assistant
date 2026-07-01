#!/usr/bin/env bash
set -euo pipefail

component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$component_dir"

if grep -R -n -E 'curl |wget |brew install|pip install|npm install|API_KEY|SECRET|TOKEN' \
  Sources tests App UITests test-fixtures MeetingAssistantNative.xcodeproj/project.pbxproj component.json README.md; then
  echo "native-app security failed: forbidden network, install, or secret marker found." >&2
  exit 1
fi

echo "native-app security check passed."
