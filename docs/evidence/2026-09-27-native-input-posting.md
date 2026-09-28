# Native input posting boundary

## Scope

The normative local posting specification and its manifest-indexed fixture were
added before the new adapter API. The manifest now indexes 109 fixtures. This
checkpoint implements the final posting boundary; it does not release the native
runtime input pause or enable client input.

A local authorization binds the existing Control session, authorization epoch,
surface ID and both surface revisions. It checks the original Control expiry and
the shorter current lease expiry independently in the host monotonic clock domain.
The Mac adapter completes asynchronous selected-app/window activation before
invoking the trusted backend executor. The authorization repeats scope and deadline
checks inside the actual synchronous posting callback. The existing adapter then
rechecks configuration and posting permission, constructs its bounded event batch,
and commits planner state only after posting succeeds.

Each invocation permits one synchronous batch. Cancellation before that batch,
a callback retained after executor return, a missing callback and a suppressed
posting failure refuse success. A duplicate callback cannot post twice. A batch
already admitted before cancellation may finish; teardown remains responsible
for releasing held input. Unsupported adapters reject the new API instead of
falling through to legacy posting.

The executor producer is still pending: it must check the current native backend,
operation, capture geometry and revocable process/input permit while holding the
permit through the synchronous batch. The existing native pause remains latched.
No authentication, pairing, approval or operation-signature bytes change.

## Verification

Candidate source input SHA-256:
`ab0ad397af29bc9e750ac06ba670444dd18d0ba08c23f7f31f3287b6080164db`.

Five Mac regression tests exercise exact scope and both deadlines, deferred and
duplicate callbacks, cancellation, expiry/backend loss across window activation,
and unsupported-adapter refusal. They construct real Core Graphics events into
an injected recording sink; they do not post system input. The activation-delay
test initially used pointer movement, which deliberately does not activate a
selected app. It was corrected to a click so it reaches the asynchronous delay.

Both experimental SDK builds bind the candidate SHA. Fifteen Simulator component
tests pass (four native video, three launch, eight UIKit owner tests). The refreshed
inventory covers six framework binaries and explicitly keeps release admission
false. Private logs and artifact provenance are under
`/private/tmp/maccompanion-sunshine-moonlight-20260926/`; the validation log is
`/private/tmp/maccompanion-native-input-posting-validation.log`.

The initial restricted Simulator build could not write Xcode compiler caches.
The authorized build with normal cache access passes. This was an environment
failure before compilation, not a native video failure.

Full `bash scripts/validate.sh` passes on stable Xcode 27.0, including all
109 indexed fixtures, the five new Mac regressions and the existing repository
policy, package and platform checks.

## Remaining work

Connect the acknowledged presentation to a current runtime/backend posting permit,
then enable the existing keyboard, modifiers, shortcuts and pointer controls using
the trusted content geometry. The previous source snapshot's two real frame /
receipt / Stop / restart cycles are recorded in the
[presentation checkpoint](2026-09-27-native-presentation-receipt.md); they are not
new end-to-end input evidence at this posting-only snapshot.

Both native input gates, permanent process/dependency/TCC admission, normal release
composition and physical installation remain open.
