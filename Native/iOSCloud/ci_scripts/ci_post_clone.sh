#!/bin/bash
set -euo pipefail

maccompanion_cloud_repository="${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1
printf 'MACCOMPANION_DEVELOPMENT_TEAM = %s\n' "${CI_TEAM_ID:?Xcode Cloud team is required}" \
  > "$maccompanion_cloud_repository/Native/iOSCloud/CloudSigning.xcconfig"
for tool in cmake xcodegen; do
  if ! command -v "$tool" >/dev/null; then
    brew install "$tool"
  fi
done
if ! brew list --versions python@3.14 >/dev/null; then
  brew install python@3.14
fi
"$(brew --prefix python@3.14)/libexec/bin/python3" "$maccompanion_cloud_repository/scripts/build_cloud_ios_dependencies.py" \
  --workspace "${CI_WORKSPACE_PATH:?Xcode Cloud workspace is required}/maccompanion-native"
