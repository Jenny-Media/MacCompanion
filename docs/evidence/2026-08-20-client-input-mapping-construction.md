# Client input mapping construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent package and iOS
Simulator compilation only

## Scope

The client now has a pure pre-sequence mapper for direct-touch and trackpad
interaction. It binds direct input to the half-open rendered-content rectangle,
rejects letterbox regions, accumulates relative trackpad motion with saturation,
balances drag transitions, resets held state on mode change, bounds scroll, and
maps a closed set of keyboard actions to the reliable input union.

A thin UIKit adapter converts recognizer locations and consumes pan translation
exactly once on the main actor. It contains no authority: every payload still
passes through `ClientInputProducerV0` for current descriptor, interaction-class,
focus, sequence, and monotonic-time enforcement.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

The validation entry point also compile-checks `CompanionClientPlatform` for
the `arm64-apple-ios17.0-simulator` triple.

Result: 51 indexed fixtures validated; all 549 Swift tests passed; macOS host
and client Network-platform targets, the iOS Simulator client-platform target,
and all three no-prompt/no-network probes compiled; `git diff --check` passed.

## Boundary not claimed

This does not instantiate UIKit recognizers or a renderer and is not physical
iPhone evidence. Orientation and scale changes, render-coordinate
synchronization, real keyboard/input methods, accessibility interaction,
coalescing/latency, background reset delivery, and device ergonomics remain
release gates.
