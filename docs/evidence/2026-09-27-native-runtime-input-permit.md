# Serialized native runtime input permit

## Implementation

The local posting specification and its sole manifest-indexed fixture were
extended before the runtime API. No remote message, authentication, pairing,
approval or signature bytes change. Existing cryptographic vectors remain intact.

The serialized menu runtime can now install the local posting primitive into an
exact paused, acknowledged Desktop session. It joins the existing host, original
Control generation and expiry, session/epoch, surface/revisions and encoded
geometry. A wrong pause fence, different generation or geometry, revoked primitive,
or attempt to replace an installed primitive is refused.

The native pause marker stays present after installation. Input retains existing
lease, class, sequence and focus checks and calls only the native adapter API with
the current short lease deadline. It never falls back to legacy posting. Renewal
retains the same primitive and original Control deadline. Pausing again,
focus/surface transition, termination and media failure revoke the shared primitive
before releasing held input or beginning cleanup. Revocation fences retained copies
and a callback already suspended on backend inspection. An already synchronously
admitted bounded batch may finish before revocation returns.

There is no production caller of this installation API yet. Connecting the
correlated presentation receipt through the Agent/menu backend owner, constructing
the current backend/process executor and enabling the UIKit controls remain next.
Normal native input remains disabled. This checkpoint does not install either app.

## Evidence

Candidate source input SHA-256:
`a171d80adddb304ed302b59ec1d244a4b29498b34cd895cf9b80263ec3cfa028`.

Four new runtime tests prove exact installation, pointer/modifier/physical-key/text/
reset delivery through the native API, renewal continuity, repeated-install denial,
re-pause/termination revocation and surface-change revocation. One new Mac adapter
test suspends backend inspection, revokes a retained copy and verifies no event is
posted. Existing native pause and final posting regressions remain in the suite.
The test executor and event sinks are injected; they do not post system input.

The surface-change test initially omitted the mandatory lease renewal-counter
increment and was rejected before transition. With that counter corrected, it
reaches preparation and verifies the old native primitive is revoked.

Both experimental iOS SDK builds bind this candidate. Fifteen Simulator component
tests pass, and the refreshed development inventory covers six framework binaries
with release admission false. Simulator UDID:
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

Full `bash scripts/validate.sh` passes on stable Xcode 27.0, including
109 indexed fixtures, the five new regressions and the existing platform,
package and policy checks. Private evidence:

- `/private/tmp/maccompanion-runtime-native-permit-validation.log`
- `/private/tmp/maccompanion-runtime-native-permit-final-tests.log`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/embedded-engine/provenance-iphoneos.json`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/embedded-engine/provenance-iphonesimulator.json`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/native-video-candidate-inventory.json`

This is runtime/adapter and Simulator component evidence. The previous
[presentation checkpoint](2026-09-27-native-presentation-receipt.md) records real
native playback; there is no new end-to-end input acceptance at this snapshot.
Permanent process/dependency/TCC admission, release composition and physical
installation remain open.
