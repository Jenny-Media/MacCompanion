# Mac local-authority UI construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; Swift package macOS compilation

## Scope

The `CompanionMacUI` package target contains value-driven SwiftUI surfaces for
exact-effect capability review, the one-session Interactive warning and local
stop, and the locally confirmed device-name editor. Pure projections preserve
all nine declared capability-effect fields, distinguish awaiting phone approval
from active control, and disable duplicate decisions or stop requests.

Views receive immutable presentation values and emit only callbacks. They do
not construct authority commands, open XPC, mutate grants, own capture/input,
or infer success before the underlying receipt-validated presentation changes.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Result

The public validation gate passed with 51 authoritative fixtures and 580 Swift
tests. It also compile-checked the new macOS SwiftUI target, both iOS client
targets, both Network-platform targets, and all three no-prompt/no-network
platform probes. SwiftPM emitted only its expected read-only user-cache warnings
in the sandbox.

## Boundary not claimed

No view was rendered or connected to an Agent. Menu-bar and window ownership,
authenticated XPC, localization review, live grant mutation, warning
visibility, keyboard navigation, assistive technologies, and physical stop
evidence require final signed identities and physical macOS execution.
