#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

python3 scripts/validate_fixtures.py
python3 scripts/validate_ci.py
python3 scripts/validate_repository_material.py
python3 scripts/validate_dependency_policy.py
python3 scripts/validate_update_policy.py
python3 scripts/validate_permanent_apple_targets.py
python3 scripts/validate_permanent_ios_target.py
python3 scripts/validate_privacy_manifests.py
python3 scripts/validate_sbom.py
python3 scripts/validate_artifact_sbom.py
python3 scripts/validate_signed_code_graph.py
python3 scripts/validate_signed_code_verification.py
python3 scripts/validate_signing_policy.py
python3 scripts/validate_signing_policy_binding.py
python3 scripts/validate_signing_policy_cli.py
python3 scripts/validate_platform_signing_fixed_tools.py
python3 scripts/validate_platform_signing_subjects.py
python3 scripts/validate_platform_codesign_verification.py
python3 scripts/validate_platform_code_signature.py
python3 scripts/validate_platform_codesign_inspection.py
python3 scripts/validate_platform_codesign_inspection_execution.py
python3 scripts/validate_platform_codesign_outer.py
python3 scripts/validate_platform_signing_evidence.py
python3 scripts/validate_platform_mac_assessment.py
python3 scripts/validate_platform_notarization.py
python3 scripts/validate_platform_notarytool_execution.py
python3 scripts/validate_package_mac_release.py
python3 scripts/validate_mac_packaging_equivalence.py
python3 scripts/validate_release_evidence.py
python3 scripts/validate_native_appearance_boundary.py

swift_arguments=(test --package-path Packages/MacCompanionKit)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  swift_arguments+=(--disable-sandbox --scratch-path /private/tmp/maccompanion-swift-build)
fi
maccompanion_test_log="$(mktemp /private/tmp/maccompanion-tests.XXXXXX.log)"
trap 'rm -f "$maccompanion_test_log"' EXIT
swift "${swift_arguments[@]}" 2>&1 | tee "$maccompanion_test_log"
# Xcode 27 beta's Swift Testing runner can return zero after reporting a target
# failure. Treat its own failure footer or failed-test glyph as authoritative.
if rg -q 'Some test targets (reported failures|did not run successfully)|✘ Test|Test run with .* failed after' "$maccompanion_test_log"; then
  echo "Swift Testing reported a failure despite the process exit status." >&2
  exit 1
fi
rm -f "$maccompanion_test_log"
trap - EXIT

network_platform_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --target CompanionNetworkPlatform
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  network_platform_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-network-platform-build
  )
fi
swift "${network_platform_arguments[@]}"

client_network_platform_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --target CompanionClientNetworkPlatform
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  client_network_platform_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-client-network-platform-build
  )
fi
swift "${client_network_platform_arguments[@]}"

ios_client_platform_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --triple arm64-apple-ios17.0-simulator
  --target CompanionClientPlatform
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  ios_client_platform_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-ios-client-platform-build
  )
fi
swift "${ios_client_platform_arguments[@]}"

ios_local_xpc_platform_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --triple arm64-apple-ios17.0-simulator
  --target CompanionLocalXPCPlatform
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  ios_local_xpc_platform_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-ios-local-xpc-platform-build
  )
fi
swift "${ios_local_xpc_platform_arguments[@]}"

ios_client_ui_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --triple arm64-apple-ios17.0-simulator
  --target CompanionClientUI
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  ios_client_ui_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-ios-client-ui-build
  )
fi
swift "${ios_client_ui_arguments[@]}"

mac_ui_arguments=(
  build
  --package-path Packages/MacCompanionKit
  --target CompanionMacUI
)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  mac_ui_arguments+=(
    --disable-sandbox
    --scratch-path /private/tmp/maccompanion-mac-ui-build
  )
fi
swift "${mac_ui_arguments[@]}"

experiment_arguments=(test --package-path Experiments/PlatformAuthorityProbe)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  experiment_arguments+=(--disable-sandbox --scratch-path /private/tmp/maccompanion-platform-probe-build)
fi
swift "${experiment_arguments[@]}"

discovery_experiment_arguments=(build --package-path Experiments/NetworkDiscoveryProbe)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  discovery_experiment_arguments+=(--disable-sandbox --scratch-path /private/tmp/maccompanion-network-probe-build)
fi
swift "${discovery_experiment_arguments[@]}"

tls_experiment_arguments=(build --package-path Experiments/NetworkTLSProbe)
if [[ "${MACCOMPANION_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  tls_experiment_arguments+=(--disable-sandbox --scratch-path /private/tmp/maccompanion-tls-probe-build)
fi
swift "${tls_experiment_arguments[@]}"

# The signed matrix is intentionally manual, but its C-only macOS 26 sources
# must continue compiling in public CI without signing, launchd, or prompts.
xpc_probe_sdk="$(xcrun --sdk macosx --show-sdk-path)"
xpc_probe_clang="$(xcrun --find clang)"
xpc_probe_flags=(
  -std=c11
  -fblocks
  -mmacosx-version-min=26.0
  -isysroot "$xpc_probe_sdk"
  -Wall
  -Wextra
  -Werror
  -fsyntax-only
)
"$xpc_probe_clang" "${xpc_probe_flags[@]}" Experiments/LocalXPCIdentityProbe/agent.c
"$xpc_probe_clang" "${xpc_probe_flags[@]}" Experiments/LocalXPCIdentityProbe/client.c
"$xpc_probe_clang" "${xpc_probe_flags[@]}" \
  -IPackages/MacCompanionKit/Sources/CompanionLocalXPCPlatformC/include \
  Packages/MacCompanionKit/Sources/CompanionLocalXPCPlatformC/CompanionLocalXPCPlatformC.c

bash -n Experiments/LocalXPCIdentityProbe/run.sh
git diff --check
