# Native presentation-to-input handoff

## Implementation

The local-backend and primary-message specifications and sole manifest-indexed
fixtures were updated before wire changes. There are still 109 indexed fixtures.
Application authentication, pairing, approvals and enrollment signing bytes are
unchanged; golden cryptographic vectors remain authoritative.

The closed local present operation requires a positive safe renderer generation
and the original enrollment challenge ID. Its receipt echoes both and requires
active/input-admitted true plus fresh operation-bound capture evidence. These
fields are forbidden on other local operations. Existing correlation, backend,
operation, runtime scope and current snapshot checks remain enforced.

The menu joins its active backend, explicit atomic-posting support and fresh
actual sample before constructing the posting primitive. It installs that primitive
through the normal serialized runtime, using the exact paused local fence. One
renderer generation/challenge is admitted per backend. Repeating that exact
presentation rechecks state/sample without replacing the primitive. A revoked
primitive cannot be revived. Stop revokes retained authorization and process
permission before awaiting cleanup; late installation cannot expose admission.

The Agent presentation operation joins any pending health read. Health readers
during presentation wait for the transition, then read fresh state. Retirement
and cancellation fence both joins. The coordinator rejoins durable/runtime
authority before and after local installation, then checks backend activity and
sample freshness again. Loss during any suspension retires the backend rather
than returning a late input admission.

The primary receipt requires inputAdmitted as a strict Boolean. False remains
observation only. The enrolled client and normal role owner now return the exact
correlated receipt after their usual current-owner checks. The native Simulator
adapter records whether it received affirmative host admission. UIKit keyboard/
pointer controls remain disabled until its current renderer owner consumes that
receipt and geometry; a frame or observation-only receipt cannot enable input.

## Checks

Candidate source input SHA-256:
`ce814217910a9166ddcd6554c4fc74368059147aafb102a50567c42a2fe50328`.

Eight added regression tests cover local presentation installation, same-generation
repetition, changed renderer/challenge denial, revoked primitive denial, missing
sample/unsupported or inactive backend, Stop during installation, closed local
fields and reply correlation, concurrent health joins, late retirement, explicit
backend admission and authority/backend/sample loss after the installation await.
Strict wire tests also reject a missing/non-Boolean inputAdmitted field. Tests use
injected executors/sinks; they do not post system input.

Full `bash scripts/validate.sh` passes on stable Xcode 27.0, including 109 fixtures,
existing crypto vectors and platform/package/policy checks. Both experimental SDK
builds bind this candidate. Fifteen Simulator component tests pass; the development
inventory covers six framework binaries with release admission false.

The live Simulator journey passes from the source-bound isolated evidence root
`/private/tmp/maccompanion-agent-xpc-evidence.82akg02o`: one UI test, zero failures,
two visible native frame / affirmative host input-permit receipt / Stop / restart
cycles on the same primary with Observe preserved. Both cycles require the
presentation-input-admitted diagnostic from the exact returned Boolean receipt.
The report records nativeHostInputPermitInstalled true, nativeInputAdmitted false
and cleanupVerified true. Client keyboard/pointer controls remain disabled.
The native source SHA matches the candidate above; combined source/helper/harness
SHA-256 is `d8fc1f191f9ea44dca05b9d55a9cd474337ebabaa0dc612d09aca0a9de3616c4`.
This proves the live host permit installation through the normal session owners,
not actual keyboard/pointer delivery or physical input/TCC acceptance.

Private logs:

- `/private/tmp/maccompanion-native-presentation-input-validation.log`
- `/private/tmp/maccompanion-native-presentation-input-tests.log`
- `/private/tmp/maccompanion-native-presentation-input-live-simulator.log`
- `/private/tmp/maccompanion-agent-xpc-evidence.82akg02o/signed-simulator-report.json`

Generated caches from the previous terminal, cleanup-verified two-cycle evidence
root were reclaimed before this run. Its binaries, reports and result bundles were
preserved. No worktree or installed product was removed.

## Remaining work

Connect this exact receipt and trusted geometry to the current foreground UIKit
native owner, then enable/test the existing keyboard, modifiers, shortcuts and
pointer controls. Native input is not yet usable end to end. Permanent dependency/
process/TCC admission, release composition, physical installation and focused
App/Window native capture remain open.
