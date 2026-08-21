# Mac pairing sheet construction evidence

Date: 2026-08-20

## Claim

`MacPairingSessionViewV0` is a value-driven SwiftUI surface over
`MacPairingSessionPresentationV0`. It renders the existing deterministic Core
Image QR only when the reducer holds a validated receipt, shows progress during
creation and cancellation, and emits one of three closed callbacks: retry the
same create command, request cancellation, or retry the same dismissal.

The sheet keeps the QR visible while cancellation is in flight or unconfirmed.
Every non-idle projection disables implicit sheet dismissal; a window close is
therefore never presented as proof that the Agent consumed the code. The
failure state explicitly says the code may remain active and offers only retry
cancellation. It contains no generic error, endpoint, fingerprint, or secret
text beyond the rendered QR itself.

## Verification

Four projection tests cover creation/retry without a QR, the explicit visible
cancel action, continued QR display through pending and failed cancellation,
and absence of an idle sheet. The hardened unsigned gate passes 803 Swift tests
and validates 616 current repository files plus 34 historical blob paths; the
Mac UI target also passes its compile check.

## Boundary

This is compile-checked package UI, not a signed or rendered final-app claim.
Permanent composition still must drive callbacks through authenticated XPC,
schedule expiry invalidation, reconcile window/Agent loss, add localized copy,
and physically verify keyboard, VoiceOver, display scaling, QR scan, and
permission/recovery behavior. The view never calls dismissal authority itself.
