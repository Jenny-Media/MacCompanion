# Initial Desktop runtime transport checkpoint

Date: 2026-08-22

## Result

The authenticated Agent-to-menu Interactive runtime transport now prepares the
initial Desktop before install. A fourth exact command carries only the
Interactive session, authorization epoch, opaque selected-display UUID, and
canonical interaction classes. The visible menu resolves that UUID through the
same process-local display mapping it published for admission and returns one
exactly correlated `AdaptiveSurfaceDescriptor`.

The menu-side preparer uses Core Graphics only to obtain bounded logical and
pixel geometry plus rotation for the already-selected display. It performs no
ScreenCaptureKit enumeration, starts no capture or input, and returns no
physical display identifier, display name, application or window identity,
permission fact, or platform object.

The install contract now carries that complete descriptor rather than only a
surface-kind value. Construction and decoding bind its session, authorization
epoch, surface, surface and coordinate revisions, and interaction classes to
the execution lease. The serialized runtime rechecks that the descriptor is a
currently valid Desktop before any indicator or capture effect, and the capture
adapter receives the complete validated install command. Renewal preserves the
installed descriptor; an explicit surface transition replaces it with the
transition's fully bound descriptor.

## Closed transport and failure behavior

- Desktop preparation, install, renewal, and revoke share one cross-family
  single-flight gate for the exact authenticated-and-ready generation.
- The preparation request and receipt use the existing 4,096-byte strict
  canonical JSON profile and asymmetric four-/five-second deadlines.
- Request/receipt mismatch, malformed data, timeout, concurrency, cancellation
  after send, replacement, or transport ambiguity retires the generation.
- The Agent route validates the receipt again before returning its descriptor.
- Non-Desktop, expired, or lease-mismatched install descriptors are rejected
  before showing the indicator or starting capture.
- The permanent menu's default construction remains inert; a runtime is
  admitted only when the same opaque display mapping can supply both admission
  publication and initial-Desktop preparation.

## Verification

- The indexed transport fixture validates with all 67 authoritative fixtures.
- Focused IPC, runtime, local-XPC, Agent-route, menu-adapter, and Desktop-preparer
  tests pass under Xcode 27 beta.
- Negative tests prove decode-time lease/descriptor mismatch rejection,
  non-Desktop and expired-descriptor zero-effect rejection, exact full-command
  capture handoff, invalid display geometry/rotation rejection, and shared
  cross-family single-flight admission.
- The complete repository gate passes 1,426 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, and eight platform-probe tests.
- `git diff --check` passes.

## Non-claims and next work

No live display enumeration, ScreenCaptureKit stream, VideoToolbox encoder,
media delivery, input posting, persistent indicator, or signed two-process
Control session ran in this checkpoint. The narrow Agent transport route and
menu runtime seam exist, but the permanent Agent still does not construct the
full Interactive runtime owner. The next checkpoint must compose that owner and
the concrete indicator, lease-expiry, capture/media, frame-blanking,
input-release, and input-posting adapters without weakening the existing
admission and teardown gates.
