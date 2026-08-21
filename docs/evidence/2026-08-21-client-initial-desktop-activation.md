# Client Initial Desktop Activation Evidence

Date: 2026-08-21

Environment: bundle-independent exact-read media and primary-channel
orchestration plus iOS Simulator cross-compilation with Xcode 27 beta. This is
unsigned construction evidence. It is not physical decoding/display, live
private-route, posted-input, stable-toolchain, signed-candidate, or release
evidence.

## Boundary completed

The selected-primary Control channel now owns the initial Desktop request,
descriptor reply, media admission, renderer-issued frame receipt,
acknowledgement request, and exact acknowledged reply. Descriptor waiting is
bounded and cancellation-aware. Input authority remains inactive until the
acknowledged reply is committed by the primary router.

The media acknowledgement fence now retains the exact first clean-keyframe
sequence instead of using a later `lastMediaSequence`. Initial acknowledgement
also requires a matching current-generation decoded-frame receipt issued only
after the concrete renderer accepts the frame. Receiving, validating, or
submitting compressed media cannot satisfy this boundary.

`NetworkClientInteractiveMediaRecordPumpV0` consumes only an authenticated
media-role socket. It reads exactly 96 header bytes, validates header bounds
before reserving payload storage, reads exactly the declared payload, leaves
following bytes untouched, and closes on truncation, malformed headers,
consumer rejection, cancellation, or end.

The configured-product binding retains the exact all-or-none ready role pair
and can construct one initial-Desktop activation owner. That owner orders the
primary descriptor request before media consumption, feeds admitted records to
an injected decoder/renderer, accepts renderer proof once, sends the exact
primary acknowledgement, and closes media/decoder state with pair retirement.
The iOS adapter composes this owner with the existing VideoToolbox decoder,
one-slot callback mailbox, display-layer renderer, and live surface while
keeping gestures disabled until the exact primary acknowledgement reply.
After that reply, one serialized input owner asks the acknowledged descriptor
authority to assign each reliable sequence, applies the 4-byte big-endian
length prefix, and sends every frame in order on the authenticated input-role
socket. Close attempts one final reset before cancelling the socket. The UIKit
factory wires gesture payloads to this owner and enables interaction only after
the active-state refresh succeeds.

That refresh now returns through the configured-product role owner into the
selected-primary application state. The exact current primary connection and
accepted interactive-session ID fence every transition through approved,
role-channel connecting, role-channel ready, initial-surface preparation, and
rendered/acknowledged active. Backward, skipped, duplicate, replaced-session,
and stale-connection progress cannot advance the revision stream. Preparation
failure records the stage without clearing the accepted-session fence, while
primary termination or replacement clears the complete Control projection.
The workspace therefore distinguishes authenticated role sockets from a
verified live surface and never enables its open action during an in-flight or
failed preparation.

## Verification

Three media-pump tests prove one-byte-fragmented exact reads without consuming
a sentinel, header rejection before payload allocation, and terminal truncated
payload cleanup. Existing client authority tests now prove exact clean-frame
sequence retention even when a later delta is already admitted, and the
selected-primary test traverses request, bounded descriptor wait, media/render
proof, acknowledgement, and reply-gated activation. A composed activation test
also proves that admitted media alone sends no acknowledgement, renderer proof
sends exactly one, the host reply advances active state, and close tears down
the renderer. The selected-primary application integration additionally proves
that approval cannot skip directly to active, progress is monotonic, effects
and expiry remain intact, a fresh exact acceptance can retry after channel
failure, duplicates do not create revisions, and stale session progress is
counted and rejected. Role-owner tests prove exact connection/session-tagged
connecting, ready, and failure publication. Workspace tests cover channel
readiness, first-frame preparation, active, failed, rejected, and disconnected
projection without conflating any pre-active state with live input.

The hardened unsigned gate passes with 62 indexed protocol/product fixtures,
746 repository files plus 34 historical blob paths and 14 repository-material
fixtures, four Swift package manifests and 12 dependency-policy fixtures,
three privacy manifests with 12 fixtures and six required-reason API source
records, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,015 Swift
tests. All macOS/iOS package cross-compiles and all three no-prompt/no-network
construction probes pass. Only the expected read-only user SwiftPM cache
warnings appear.

## Remaining gates

- Prove real H.264 decode/display, exact blanking, input effects, replacement,
  backgrounding, lock fallback, and latency on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
