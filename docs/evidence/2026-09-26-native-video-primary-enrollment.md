# Native video enrollment through the authenticated Control channel

Date: 2026-09-26. This completes the primary-message enrollment connection.
It does not claim automatic normal-app native playback or a signed installation.

## Changes

The normative primary profile and six fixtures were added before the closed
wire records. The sole fixture manifest now indexes 100 JSON fixtures. These
requests use the authenticated primary's Control lane; Observe and Act grants
remain independent. The existing session-signature golden vector is unchanged.
Public fixture DER bytes are non-certificate samples accepted only by fake
backends. No real credentials were added to the repository.

The normal host dispatcher routes enrollment request/proof/cancel to an optional
native bridge. It obtains the registered session public key from the durable
admission snapshot and rechecks admission after bridge work. Native generations
increase independently of WebRTC generations. Session End, primary loss, local
Stop, and surface replacement retire native work before replacement capture.
The bridge reserves construction and proof transitions, joins one drain, rejects
parallel proofs, and prevents old cleanup from closing a replacement operation.

The Agent root constructs the native coordinator reader from the same reconciled
store used by Control admission. Platforms supply only an acknowledged Desktop
runtime snapshot and an inert backend factory. Display, visible-menu generation
and revision, original Control binding/deadline, and surface geometry must match.
Admission is checked before and after backend construction and throughout the
coordinator lifetime. A platform cannot substitute a durable key or grant reader.

The normal client channel owns correlated bounded challenge/proof/cancel waits,
rejects stale results, and retains the original local Control deadline. Concurrent
cancellation joins one waiter. The client enrollment session reconstructs the
signature through the existing attestation owner and session-key custody. It
fences before cleanup, cancels pending work, rejects late signatures, and monitors
current Control authority. The network role product owns this session and closes
it when the role pair retires. Enrollment completion grants no input or displayed
frame acknowledgement.

## Verification

Selected stable Xcode: `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0.

- Focused tests passed: 35 native signing/wire/lifecycle/challenge/coordinator/
  bridge/client-attestation XCTest checks, 22 host-dispatcher Swift Testing
  functions, and four client-primary functions (the normal approval/enrollment
  journey covers three delivery orders).
- Added bridge checks cover Stop during pending construction, parallel proofs,
  wrong challenge correlation, mismatched runtime display, revocation during
  backend construction, and live durable-grant loss.
- Each client delivery order exercises challenge/proof/ready/drained cancel
  through the normal primary router, then simultaneous Stop calls while a new
  enrollment request is pending. Signing must not be reached after that Stop.
- Full `bash scripts/validate.sh` exited 0; `git diff --check` passed.
- Twelve extracted native lifecycle/owner tests passed in the dedicated Simulator.
- The normal integrated Control Simulator suite passed all three UI journeys,
  including reconnect/replacement and stale-callback retirement; the subsequent
  five pairing reliability checks passed. These journeys exercise the existing
  media path, not automatic native playback. Evidence remains outside Git at
  `/private/tmp/maccompanion-feature-tests.RljA4v` (exit 0).
- Simulator and iPhone SDK components built; all six framework records match
  the same current source inventory.
- The isolated actual Sunshine backend probe passed again: attested certificate
  access, rejection of another certificate, busy-port rejection, invalid DER/
  proof rejection, revocation, and owned private-state cleanup. That probe still
  uses synthetic Control authority and is not an authenticated normal-app journey.

Current source-input SHA-256:
`51e53b3117cfc6f019861efcab3b75dcebb5c8fa795939d5fba9c8f7f86677b4`.
Probe executable SHA-256:
`eeb58412fa0d0e3a29b727b9b59a47f5affc91d9b09c59a98171e2532321b8e2`.
Sunshine executable SHA-256:
`e03e5015c9fd1c8f70c5d0c4078cb2e4f8516cc4c928276c78d14e0c8fa19dcf`.

Local diagnostic reports and private test artifacts remain outside Git under
`/private/tmp/maccompanion-sunshine-moonlight-20260926`.

## Remaining integration

1. Implement the native client ephemeral identity, pinned mutual TLS, HTTPS
   launch, encrypted stream configuration, and credential erasure adapter.
2. Implement the authenticated Mac runtime snapshot/backend provider. The
   production Agent currently has no concrete native provider; the existing
   Sunshine backend remains an isolated loopback experiment. Seal upstream
   management/pairing routes before exposing a managed host to the phone.
3. Connect admitted adapters to automatic normal UIKit startup. Current
   enrollment still requires the existing acknowledged initial Desktop path;
   it has not replaced the H.264 initial-frame handshake.
4. Define native presentation receipts and preserve existing input/surface
   authority before enabling touch, keyboard, modifiers, and focus input.
5. Complete corresponding-source/dependency and process/TCC packaging gates,
   then produce and test signed normal-app candidates on the Mac and iPhone.

No new app was installed. Native input remains disabled. This checkpoint makes
the authenticated enrollment connection concrete without claiming a completed
usable engine replacement.
