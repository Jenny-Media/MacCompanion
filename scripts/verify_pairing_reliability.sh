#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
developer_root=${MACCOMPANION_DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
package_path="$repository_root/Packages/MacCompanionKit"
derived_root=${MACCOMPANION_PAIRING_DERIVED_DATA:-/private/tmp/maccompanion-pairing-reliability}

cd "$repository_root"

python3 scripts/validate_fixtures.py

DEVELOPER_DIR="$developer_root" swift test \
  --package-path "$package_path" \
  --filter goldenCryptoVectorMatchesEveryNormativeConstruction
DEVELOPER_DIR="$developer_root" swift test \
  --package-path "$package_path" \
  --filter authoritativePairingFixturesDecodeAndCanonicalize
DEVELOPER_DIR="$developer_root" swift test \
  --package-path "$package_path" \
  --filter lostPairingCompletionRecoversExactDurableDeviceEndToEnd
DEVELOPER_DIR="$developer_root" swift test \
  --package-path "$package_path" \
  --filter clientPairingApplicationOwnerRecoversDroppedCompletionWithoutRescan
DEVELOPER_DIR="$developer_root" swift test \
  --package-path "$package_path" \
  --filter lostCompletionRecoveryRemainsVisibleAndAcceptsOnlyExactAttempt

if [[ ${1:-} != "--signed-builds" ]]; then
  echo "Pairing reliability checkpoint passed (bundle-independent)."
  exit 0
fi

if [[ -z ${MACCOMPANION_DEVELOPMENT_TEAM:-} ]]; then
  echo "MACCOMPANION_DEVELOPMENT_TEAM is required for --signed-builds" >&2
  exit 2
fi

DEVELOPER_DIR="$developer_root" xcodebuild \
  -project MacCompanion.xcodeproj \
  -scheme MacCompanion \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_root/mac" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$MACCOMPANION_DEVELOPMENT_TEAM" \
  build

DEVELOPER_DIR="$developer_root" xcodebuild \
  -project MacCompanion.xcodeproj \
  -scheme MacCompanionIOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_root/ios" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$MACCOMPANION_DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY='Apple Development' \
  build

codesign --verify --deep --strict \
  "$derived_root/mac/Build/Products/Debug/Mac Companion.app"
codesign --verify --strict \
  "$derived_root/ios/Build/Products/Debug-iphoneos/Mac Companion.app"

echo "Pairing reliability checkpoint passed, including signed Mac and iOS builds."
