# Concrete macOS Interactive effects

Date: 2026-08-22

## Result

The permanent Mac Companion menu application now constructs the concrete
Desktop Control runtime instead of the unavailable placeholder. Construction
remains effect-inert. An authenticated, ready Agent generation must publish the
opaque selected display, validate current durable and visible admission, issue
an exact short-lived execution lease, and receive a correlated runtime receipt
before the secondary Interactive channels can carry input or media.

The indexed `mac-interactive-platform-effects-v0.1.json` fixture freezes the
release profile for this slice:

- Desktop-only ScreenCaptureKit capture at no more than 1,920 by 1,200,
  30 frames per second, queue depth 3, and one newest callback;
- real-time VideoToolbox H.264 with no frame reordering, an 8 Mbps target,
  a two-second keyframe interval, one in-flight frame, and one newest waiter;
- an eight-record, 16 MiB, non-evicting media queue with one acknowledged
  local-XPC publication in flight; and
- pointer, keyboard, and text construction through Core Graphics, with exact
  display geometry and runtime-fence validation before posting to the HID tap.

## Ownership and failure behavior

`MacInteractiveControlRuntimeCompositionV1` owns one complete capture graph for
the exact initial Desktop descriptor. It re-resolves the process-local opaque
display mapping before and after ScreenCaptureKit enumeration, constructs the
encoder and stream only after input-post permission preflight succeeds, and
retains them until ordered runtime cleanup. Display loss, capture failure,
invalid samples, encoder failure, publication rejection, or queue overflow
invalidates the exact Agent authority and enters the existing four-effect
cleanup path.

`MacCoreGraphicsInteractiveInputAdapterV1` is the sole release boundary that
posts Core Graphics events. It never requests Accessibility permission in
response to remote traffic. It requires a positive
`CGPreflightPostEventAccess` result, independently reconstructs the active
session/epoch/surface/coordinate fence, plans on a copied state value,
constructs the complete batch, posts under one lock, and commits pressed-input
state only after construction and posting succeed. Cleanup releases every
tracked button, key, and modifier before capture stops.

`MacLocalXPCInteractiveMediaDrainClientV1` installs the queue's sole exact-token
wakeup owner. It dequeues one complete record and awaits the corresponding
authenticated local-XPC acknowledgement before dequeuing the next. Failure or
cancellation atomically removes the callback, cancels the drain, and closes the
client generation. Queue purge remains ordered before retained-frame blanking.

If the permanent app cannot establish its initial physical-display mapping or
construct the fixed bounded queue, it installs the existing unavailable
runtime and grants no Control authority.

## Verification

- The fixture validator accepts 71 indexed JSON fixtures, including the new
  concrete-effects contract and exact manifest digest.
- Focused tests prove inert composition, permission-denied setup without an
  event, exact fence rejection, selected-display pointer mapping, no planner
  commit after failed event construction, balanced release, sole queue-wakeup
  ownership, one-record XPC backpressure, and terminal callback withdrawal.
- A pre-existing route-racing test barrier that could release a synthetic
  winner before all injected attempts entered was made deterministic and
  passed 20 consecutive isolated repetitions.
- The complete Swift Testing catalog contains 1,461 tests. Repository-wide
  validation passes the fixture, repository-material, dependency, permanent
  target, privacy, SBOM, signing, notarization-construction, packaging,
  appearance, macOS/iOS cross-build, and eight platform-probe gates under the
  installed Xcode 27 beta.
- An explicit code-signing-disabled Debug build of the checked-in
  `MacCompanion` Xcode scheme compiles and links the permanent app, embedded
  Agent, new ScreenCaptureKit/VideoToolbox/Core Graphics composition, and the
  changed application constructor for arm64 macOS 26.0.

## Non-claims and next evidence

This is compile-tested and fault-injected construction evidence. It does not
claim a signed live ScreenCaptureKit session, a real Accessibility/TCC grant,
posted physical input, encoded pixels reaching a physical iPhone, decoder or
renderer latency, lock-screen operation, final-identity local XPC, stable Xcode
26.6 compatibility, or external-beta acceptance. Application, window, focused
region, and surface-transition capture remain unavailable in this concrete
adapter; a transition request fails closed and ends the session through the
existing runtime policy.

The next Control proof is a signed two-process Mac run with ordinary screen
recording consent and explicitly granted input-post access, followed by a
physical iPhone end-to-end Desktop stream, pointer/keyboard exercise, local
Stop, lease expiry, display loss, permission loss, lock/takeover, latency, and
reconnect evidence. Persistent capture remains an independent Apple-managed
entitlement gate and is not required for this ordinary-consent slice.
