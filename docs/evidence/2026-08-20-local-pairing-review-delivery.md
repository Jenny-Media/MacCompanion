# Local pairing review delivery evidence

Date: 2026-08-20

## Claim

The secret-free pairing review now has a complete bundle-independent path from
the host pairing wire owner to a trusted local Mac presentation and back to the
Agent decision authority. `AgentLocalPairingReviewServiceV0` is a
connection-scoped capability issued by `AgentLocalServiceRootV1` only after a
future platform adapter authenticates the visible menu-app endpoint. It accepts
no caller role, audit token, endpoint label, or authorization assertion.

The service acknowledges publication only when the exact review still equals
the pending value in `AgentLocalPairingDecisionHandlerV0` and the Mac surface
has retained it. It owns at most one publishing, visible, or resolving review.
Exact duplicate publication is idempotent; a different, unregistered, stale,
withdrawn, or concurrently replaced review fails closed. Review withdrawal is
exact-ID-bound on host completion, decline, expiry, disconnect, cancellation,
publication failure, or endpoint loss. Endpoint loss cancels a still-pending
decision but cannot interrupt a durable decision already in flight.

`MacPairingReviewApplicationOwnerV0` and
`MacPairingReviewPresentationV0` retain the immutable Agent review, begin with
an empty local name, and emit an approval only after the draft validates as a
`DeviceDisplayName`. Decline carries no name. A failed local response retains
the exact command and command ID; the user cannot edit it into another name or
decision. Delayed receipts, expiry, withdrawal, and Agent invalidation are
revision-fenced. The SwiftUI `MacPairingReviewViewV0` renders the exact SAS,
local name field, progress, decline/approve actions, and exact-retry state
without a remote-supplied name or implicit dismissal.

The Agent decision handler remains the only semantic, durable-outcome, and
receipt-replay authority. The delivery service stores no pairing secret,
device keys, grants, durable approval, or independent completion result.

## Verification

Six Agent service tests prove exact-pending publication, idempotent duplicate
delivery, rejection and compensation, exact approval/withdrawal/replay,
retryable durable failure, suspended-publication withdrawal fencing, and
endpoint-loss cancellation. Ten host wire-owner tests prove exact withdrawal
on approval, decline, expiry, publication failure, and cancellation, including
early terminal closure when a registered local review becomes unavailable.

Six Mac application/presentation tests prove empty local naming, approval and
decline shape, invalid-name rejection before command-ID consumption, exact
lost-response retry, correlation-gated success, exact expiry/withdrawal, and a
delayed-receipt fence. Four Mac UI projection tests prove exact SAS display,
name editability only before decision, progress, exact retry, and no idle
surface. `CompanionAgent` passes 154 tests, `CompanionMacApp` 16, and
`CompanionMacUI` 19.

The exact hardened validation command passes 60 indexed protocol/product
fixtures, 655 repository files, every package/platform build, all three
no-prompt/no-network probes, and exactly 887 Swift tests under the provisional
Xcode 27 beta toolchain. The gate also tightened an existing capture-owner
test to await the complete terminal postcondition rather than racing the
intentional fail-first asynchronous cleanup sequence.

## Boundary

This is bundle-independent construction and compile evidence. It does not
authenticate an XPC audit token or designated requirement, create a permanent
endpoint, prove signed process identities, demonstrate UI recovery after a
real menu-app crash, review localization/accessibility on physical hardware,
or complete a physical QR/TLS/SAS exchange. Those remain gated on final Apple
identities, the stable release toolchain, signed targets, and physical-device
evidence. The public root factory is a capability-issuance seam, not caller
authentication; a release adapter must never expose it before the closed local
role policy succeeds.
