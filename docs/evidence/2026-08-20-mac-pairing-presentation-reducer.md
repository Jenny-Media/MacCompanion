# Mac pairing presentation reducer evidence

Date: 2026-08-20

## Claim

`MacPairingSessionPresentationV0` now provides the menu app's pure state
boundary for secret-bearing create and dismiss IPC. It emits typed commands,
accepts only exactly correlated receipts, keeps the QR visible while a
dismissal response is unresolved, and returns to idle only after an exact
dismissal receipt whose completion time does not predate QR creation.

A failed create or dismiss response retains the original command. Explicit
retry re-emits that exact value, preserving the Agent handler's idempotency
contract if the mutation succeeded but the response was lost. Agent loss,
listener loss, logout, expiry notification, or local presentation teardown may
call `invalidate()` from any phase; the reducer immediately removes the QR
receipt and returns to idle.

## Verification

Five tests cover the complete create/show/dismiss flow, exact create retry,
exact dismiss retry, correlation and time-regression rejection, and secret
erasure from a failed-dismiss state. The hardened unsigned gate passes 799
Swift tests and validates 613 current repository files plus 34 historical blob
paths. The subsequent value-driven Mac sheet raises current hardened coverage
to 803 Swift tests and 616 repository files.

## Boundary

The reducer owns no transport, XPC identity check, random generator, clock,
pairing authority, or SwiftUI lifecycle. Permanent app composition must create
cryptographically random command IDs, drive the reducer only from the
designated-requirement-authenticated XPC adapter, render its visible receipt,
and call Agent dismissal before treating a user close as complete. Signed UI,
connection invalidation, accessibility, expiry scheduling, and physical scan
remain release evidence.
