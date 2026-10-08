# Selected stream adapter and Sunshine frame handoff

## Implemented

`Native/Host/CompanionSelectedCapture` consumes a local ScreenCaptureKit filter
and immutable source/encoded geometry. Construction is inert. It configures
aspect fit, bounded output, no audio and no window shadows. The trusted local
caller supplies the current selection/Control predicate; the adapter checks it
before starting and before each frame. It creates no approval or input route.

Its serial owner handles start, frames, revocation and Stop. Stop fences frames
and joins a pending start before requesting platform stop, so an early stop
acknowledgement cannot precede a later successful start. Terminal completion is
once, after the platform stop acknowledgement or an actual platform stop event.
The owning process remains responsible for its existing bounded lifetime.

Only fresh complete samples reach the frame callback. Image/format dimensions,
pixel format, full clean aperture, content placement/scaling and increasing
monotonic display time must match. Idle/blank frames do not refresh evidence.
Malformed, changed, future, stale or reordered complete samples terminate.
Live ScreenCaptureKit content-placement interpretation remains to be verified;
synthetic matching metadata alone cannot open native presentation/input gates.

The pinned Sunshine patch adds an inert selected-filter constructor to its
`AVVideo` capture API and routes selected samples into its existing frame
callback and private sample-report path. Every capture invocation creates its
own adapter. A terminated last selected stream removes its sample report.
Failure wakes the waiter with a latched failure; streaming returns an error and
encoder probing refuses success without an image. The Desktop constructor
still serves the current managed process; nothing selects this new constructor
from the normal backend yet.

The explicit development host builder compiles the first-party adapter with ARC
and links ScreenCaptureKit. Its record binds both source hashes. Archive rebuild
remaps the selected-source path into the extracted workspace and checks those
hashes; it cannot silently compile this adapter from the live original tree.
Native candidate input hashing now includes all `Native/Host` source files.

## Verified

The normative component contract and indexed lifecycle fixture preceded the
implementation. Fifteen deterministic native lifecycle/sample cases pass,
including Stop during start, a frame before the start reply, revocation, idle,
changed geometry/scale, malformed status and future/reordered timestamps.
Three bridge conditions also pass against the actual patched `AVVideo` object:
bounded failure wakeup without callback, failure remaining latched and invalid
source dimensions rejected. These tests use synthetic samples and an inert
local transport; they enumerate no windows and request no capture permission.

Private focused log:
`/private/tmp/maccompanion-selected-stream-and-bridge-tests-20260927.log`, SHA-256
`3afb78b7cafff4b266059700393c374b09024a6281682656d42e2ad1cef14327`.

The final source-built host completes configure, compile, link and dependency
readback at `/private/tmp/maccompanion-selected-capture-host-20260927-v2`.
The adapter class and ScreenCaptureKit dependency are present in the linked
binary. Host binary SHA-256:
`0a48b40d67d7df597735d436e52f22253d3a584c38645d130e080360d3711b85`.
Provenance SHA-256:
`9ab8b22e7c6b28fef025956ac0c8671c11943e029bf64b635c68953dc2a89494`.
Pinned complete managed patch SHA-256:
`1966cf6d8eca6fa40df86e976ab73d000e3254c822742eb9fd62703d429c9555`.
Adapter header SHA-256:
`31f4d8a22160315fdf3e32671505816b30db3cd76885abc0f9780c4624691159`.
Adapter implementation SHA-256:
`524045285c3e2c69cd1db9909d52f042b297c57f6ff9a8c407628a8a4f75febe`.
An earlier v1 build preceded the failure-propagation fix and is superseded.

Final required stable `bash scripts/validate.sh` passes with 114 indexed fixtures,
all package/lab tests and platform builds, including the native component cases
and all 131 Agent platform tests. Private log:
`/private/tmp/maccompanion-selected-stream-storage-final-validation-20260927.log`,
SHA-256 `718ff617c47c45aa9abb5e99d03fad7aebf9f92ac3d80f0804d5ba17345863e2`.
Current aggregate native source input SHA-256:
`6ef1493a1ea7de53ba70e24212ef18f8435c53107aa63c686684522b47ecbee2`.
This source input has no new normal client/Simulator playback acceptance.
An earlier full run terminated a storage-test process; the
[descriptor ownership evidence](2026-09-27-store-initialization-descriptor-ownership.md)
records its actual crash and repair rather than treating that run as passed.

## Remaining integration

This is a compiled local capture API, not native App/Window acceptance. The
managed process needs a trusted selection handoff bound to its exact current
operation and live window/process/bounds checks. ScreenCaptureKit objects remain
menu-local in the existing target owner; this constructor cannot by itself move
those objects across a process boundary. Resolve that handoff explicitly under
the normative privacy and process contract, without adding physical selection
identifiers to the Agent or remote protocol.

Then verify actual selected pixels and content placement, update the normative
App/Window enrollment/admission contract, and open the current Desktop-only
runtime/client gates. Rebuild the source-pinned host/client/normal artifacts
before a fresh normal Simulator journey. No selected-window/App pixels, new
normal Simulator playback, installed Mac, physical phone, input effects or TCC
acceptance are claimed here. Viewport bitrate and current corresponding-source
assembly remain pending.
