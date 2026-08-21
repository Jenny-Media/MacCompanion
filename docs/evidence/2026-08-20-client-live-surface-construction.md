# Client live-control surface construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; package and iOS Simulator compilation

## Scope

The client now has a compile-checked SwiftUI-to-UIKit live-control surface.
One stable main-actor session owns a UIKit video surface, VideoToolbox decoder
coordinator, and gesture recognizers. SwiftUI supplies declared encoded
dimensions, interaction mode, and whether input is currently authorized; it
never owns pixels, gesture state, or input sequence authority.

Pure aspect-fit geometry maps the view bounds to the exact rendered-content
rectangle for direct touch and trackpad input. UIKit emits tap, one-finger
pointer movement, long-press drag, and two-finger scroll payloads synchronously.
Mode, geometry, disable, failure, and dismantle paths reset held input. SwiftUI
dismantle terminates the decoder/mailbox session and removes the displayed
image, preventing an in-flight callback from repainting a detached surface.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Result

The public validation gate passed with 51 authoritative fixtures and 574 Swift
tests. It also compile-checked both `CompanionClientPlatform` and
`CompanionClientUI` for iOS Simulator, both Network-platform builds, and all
three no-prompt/no-network platform probes. SwiftPM emitted only its expected
read-only user-cache warnings in the sandbox.

## Boundary not claimed

No recognizer or renderer was instantiated. Gesture arbitration, pointer feel,
long-press timing, hardware keyboard input, accessibility alternatives,
orientation changes, background transitions, decoder races, screenshots, and
end-to-end latency require a physical iPhone/iPad and live Mac session.
