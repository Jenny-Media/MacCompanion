# Native playback with the normal Desktop geometry

## Change

The authenticated native experiment previously declared a generated 640×480
logical Desktop while Sunshine captured the actual selected Mac display. That
substitute could prove video and cleanup but could not establish correct pointer
coordinates for native input.

Both native experiment modes now use `MacInteractiveInitialDesktopPreparerV1`,
the normal menu-owned Desktop projection. The opaque selected display resolves
locally; its logical bounds, rotation and chroma-aligned capture profile enter
the existing descriptor. Generated bootstrap pixels are encoded at that exact
descriptor size. The native adapter then launches Sunshine at the same size.
The CLI probe also derives its launch size from the descriptor instead of a
hard-coded mode.

A narrow experimental wrapper verifies the prepared logical bounds and capture
profile against the selected display catalog. The live verifier requires this
geometry check twice, once per fresh session. No physical display ID is logged
or added to a wire record. Existing projection and descriptor semantics are
reused; no new protocol, signing or input admission is introduced.

## Evidence

Stable Xcode 27.0 (27A266a), macOS 27.2; dedicated iOS 27.0 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

The finalized report
`/private/tmp/maccompanion-agent-xpc-evidence.or7o8dt8/signed-simulator-report.json`
records one UI test passed, zero failures, and verified cleanup. It covers two
actual native displaying/pixel checks, continuous bootstrap, Stop and fresh
restart through normal UIKit owners, real pairing, authenticated primary TLS
and signed Mac XPC. Same-primary Observe remains available. Private attachments
were inspected and show streamed desktop content; no screenshot was added to Git.

Combined app/harness/signed-helper source fingerprint:
`b6e948a6fea9c2b091c0269e0b6d82d753896fbf8ac73a6c5a471c0c3acc1be9`.

The separate signed host lane passed all four stages and verified cleanup in
`/private/tmp/maccompanion-agent-xpc-evidence.isqkruxf/native-report.json`.
Actual enrollment, mutual TLS/Desktop launch, two lease renewals and Stop
preserving Observe pass with the projected descriptor. Local XPC source hash:
`e5be6ad686474a5f459af2257c5bfb7fc14821996d98f1f128fb36dd7d6eb555`.

Read-only Core Graphics inspection found logical bounds 2560×1067 and capture
mode pixels 5120×2134, with zero rotation. The normal profile selects 1920×800
encoded output. This distinction is why the logical Desktop must not be derived
from either the test bootstrap size or encoded pixel count.

This change is confined to experimental composition and verification. Native
candidate inputs retain SHA-256
`11caac034b66d8b269c3602c5549299a08c66977d735c4e6198519e711ec0218`,
matching both SDK builds, fifteen native component tests and the six-framework
inventory from the [Stop checkpoint](2026-09-27-continuous-native-stop.md).
Those components did not require another rebuild for this experiment-only change.
Final stable `bash scripts/validate.sh` passed; its private log is
`/private/tmp/maccompanion-native-geometry-validation.log`. `git diff --check`
passed.

## Remaining work

Native input remains disabled. A native presentation acknowledgement must be
specified, fixture-backed and joined to the host input gate before existing
pointer/keyboard controls can be enabled. Capture/content bounds and viewport
mapping must account for aspect-fit padding and chroma rounding rather than
assuming the complete encoded frame contains desktop pixels. Rotated displays,
geometry changes during a session and focused App/Window capture are not accepted
by this Desktop-only live test.

Software custody/consent, generated bootstrap/indicator/input effects and
disposable signed helpers remain test substitutes. Permanent dependency/process/
TCC admission, normal target composition, installation and physical acceptance
remain open. Installed normal apps and the physical iPhone were untouched.
