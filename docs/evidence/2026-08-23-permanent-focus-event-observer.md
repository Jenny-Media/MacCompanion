# Permanent focus-event observer

Date: 2026-08-23

## Outcome

The production Agent product now owns a lifecycle-bound focus observer. After
the local menu generation and shared network listener are ready, it polls the
privacy-filtered focus snapshot at 250 ms and publishes an ordered
`interactive.surface.focusChanged` event through the active authenticated
application-primary connection. It does not poll Accessibility when there is
no matching authenticated primary or no acknowledged Interactive surface.

The event readiness proof carries the exact 16-byte primary connection ID from
the last authenticated Interactive command. Both the pre-sample availability
check and the final send require that exact server-issued ID. A replacement
primary therefore cannot trigger focus sampling or receive the previous
primary's Interactive event. The host session reveals this ID only after
authentication is ready and clears it during terminal teardown.

The observer permits one outstanding event per exact session, authorization
epoch, surface ID, surface revision, and coordinate-space revision. A menu
generation invalidated during a suspended snapshot cannot return a usable
candidate. A send failure or primary-replacement race revokes the prepared
one-use focus token and closes the surface-control session instead of leaving
input authority ambiguous.

## Lifecycle and authority

- The stable candidate source binds only the current authenticated menu
  generation and rejects stale, duplicate, invalid, and terminal bindings.
- The Agent surface handler caches authenticated principal facts only after the
  initial surface acknowledgement. Background events may refresh host state
  and clocks, but cannot replace device, client, authorization, grant, policy,
  host identity, fingerprint, or primary binding.
- Host state must remain `userSessionActive`, and refreshed wall and monotonic
  clocks cannot move backward.
- Product finish stops the observer and invalidates its candidate source before
  tearing down Interactive runtime and network ownership.

## Verification

- Observer tests prove no sampling without a primary, no sampling through a
  replacement primary ID, one publication per exact surface fence, and
  revoke-plus-close behavior on a publication race.
- Ingress tests prove the event follows the exact current primary generation,
  rejects the old connection ID after replacement, and becomes unavailable
  after cancellation.
- Surface-authority tests prove readiness returns the authenticated primary ID
  and that background event creation reuses the authenticated session facts.
- The repository-wide gate passes 73 indexed fixtures, all 1,493 discovered
  Swift tests, macOS/iOS cross-builds, unsigned permanent application builds,
  and eight platform authority probes on Xcode 27 beta.

This checkpoint does not yet construct a live focused-region ScreenCaptureKit
crop or apply the received event automatically on iOS. It makes no signed-
device, TCC, latency, or lock-screen claim.
