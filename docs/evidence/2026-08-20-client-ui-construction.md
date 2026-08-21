# Client pairing and host-summary UI construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; package and iOS Simulator compilation

## Scope

The new `CompanionClientUI` package target consumes the existing pure
presentation reducers and emits only closed callbacks. Its pairing surface
visibly distinguishes scan, unverified preview, pinned security progress,
verified Mac comparison code, durable saving, paired, and closed failure
states. Its host summary keeps connection, view-only, control, lock-paused,
approval, starting, and teardown states distinct and makes Remote Control an
optional action from an otherwise useful connected Mac.

The views use native labeled buttons and progress views, scrollable
Dynamic-Type-friendly layouts, coarse route descriptions, locally confirmed
Mac names, and an explicit accessibility label/value for the authentication
code. No QR secret, raw route, discovery identity, remote error text, grant
mutation, or service call enters view state.

The same target adds a surface picker that presents Desktop plus short-lived
opaque application/window choices. It uses sanitized application names and
window ordinals only, keeps unavailable targets visible but disabled, and
states explicitly that window titles and document names remain on the Mac.

## Result

The public validation entry point passed with 51 indexed fixtures and all 570
Swift tests, including ten focused UI-projection tests. The same run
compile-checked both `CompanionClientPlatform` and `CompanionClientUI` for the
arm64 iOS 17 Simulator, completed both Network-platform builds, and passed all
three no-prompt/no-network platform probes.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Boundary not claimed

The SwiftUI target is compile-checked but not hosted in an app target. Camera
capture, real navigation, localized copy, live service wiring, preview
rendering, VoiceOver/Voice Control, Dynamic Type screenshots, contrast,
orientation, and physical pairing/control flows remain release evidence.
