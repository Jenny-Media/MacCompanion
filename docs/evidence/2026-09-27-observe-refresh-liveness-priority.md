# Manual Observe refresh behind a background liveness check

## Reproduction and scope

A deterministic test against the actual `ClientObserveChannelV0` reproduced a
manual-refresh collision: after sending an automatic liveness status request,
calling `requestStatus()` before its reply threw `statusRequestPending`. The
normal workspace forwards that error to the Command did not complete alert.
This establishes a concrete product defect independently of native video.

The earlier recovery v2 failure occurred on Refresh Status after backgrounding
and Stop, but did not record its error case. This collision is a plausible cause
of that failure, not a retrospective proof. Content-free diagnostics remain
enabled; a different command failure must still be investigated on its evidence.

The private reproduction log is
`/private/tmp/maccompanion-observe-refresh-collision-reproduction-20260927.log`,
SHA-256 `e44f409d1fefc30e6829e1eed48825c9a5ac7d7c853e090e2c0dd7597952773c`.
Its one passing test asserted the old error behavior before the fix. That test
has been replaced by acceptance tests for the corrected ordering.

## Implementation

The normative Observe contract and sole authoritative fixture manifest were
updated before implementation. One manual intent can reserve the status lane
behind a pending background liveness check. The router's committed, exact
correlated reply releases it. The manual refresh then issues its own request
with a new message ID and monotonic start time. Only its own validated reply
updates user-visible status; the heartbeat sample remains unretained/unpublished.

Other manual refreshes and automatic checks cannot overtake the reservation.
Cancellation discards only that local intent. Invalidation or a rejected reply
fails it without a late send. A correlated heartbeat error permits a separate
manual attempt. A ten-second local timeout likewise fails the waiting attempt
without sending it, canceling the heartbeat, or relabeling cached status live.
The timer is canceled when the reservation resolves. The normal UI shows
Refreshing Status and disables repeat taps while the command is waiting.

At most one status wire request and one local manual reservation exist. The
change adds no wire messages, grants, pairing, approval or signature semantics.
Observe/Act/Control independence, exact correlation, router commit fences,
connection generation, replay protection and conservative freshness remain.

## Targeted acceptance

Stable toolchain: 13 Observe tests pass, zero failures. Six new tests establish:

1. A manual refresh waits for liveness and then publishes only its separate
   reply; its freshness round trip begins when that manual request is issued.
2. Cancellation sends no manual frame and preserves independent liveness.
3. Invalidation between reply preparation and router commit cannot release a
   late manual request.
4. Rejected liveness correlation fails the reservation without sending it.
5. A correlated liveness error allows a separate manual attempt and publishes
   no fabricated status/error sample as Observe state.
6. Reservation expiration sends no manual frame and preserves the heartbeat;
   a later explicit manual request still works after the heartbeat completes.

Private targeted result:
`/private/tmp/maccompanion-observe-refresh-priority-final-tests-20260927.log`,
SHA-256 `ed826fe1ab9592bd8e7af8ccfb7b1c22538665441bd3d5a4843b674b6fa46416`.
The indexed `client-observe-liveness-priority-v0.1.json` is a local composition
contract fixture, not a second wire or cryptographic fixture corpus.

## Normal app acceptance

Both native SDK builds and normal iOS app builds pass. The iPhone SDK build is
unsigned and uninstalled. Required stable `bash scripts/validate.sh` passes,
including 111 indexed fixtures, and `git diff --check` passes. The final record is
`/private/tmp/maccompanion-observe-priority-bounded-validation-20260927.log`.

The full normal Simulator recovery journey **fails on a different path** after
its first native session, background fencing/restart guidance, Stop and live
Observe refresh pass. The second Control request immediately retires back to
the workspace; no top Stop appears. Content-free diagnostics record
`interactive.activation.fail-closed` and `ui.render-receipt.terminal` with
`ClientInitialSurfaceErrorV0`. That screen-receipt failure requires its own
reproduction and fix; this candidate does not have complete native recovery
acceptance. The runner conservatively leaves all full-journey acceptance flags
false when its selected UI test fails.

The failed UI journey takes 121.874 seconds. Exact pair-key cleanup, disposable
host retirement and original owned Simulator app/data restoration pass. The
test does not reach the connection-loss step. Previous guidance-candidate
recovery passes retain their original source pins and cannot be applied to this
new candidate. No installed Mac app, physical phone, LAN or TCC state is changed.

Private failed journey:
`/private/tmp/maccompanion-normal-observe-priority-recovery-20260927-v1/report.json`.
Report SHA-256:
`801f27c422ba62b913d9f4e0635c8cbc280cc9aa305c3bbf98a094f4140432d3`.
Exact-key cleanup passes in 0.045 seconds, zero failures.
Normal source-input SHA-256:
`2b204ddcf4f76fa36589e10d6ba4c9c300c86039fbc915202a60203b1869d125`.
Tested normal executable SHA-256:
`b576cec63df1839290dcfbab4db2debc0e71ce159c2869de17466ad92cf72db7`.

## Next

Subsequent checkpoint: [initial acknowledgement ordering](2026-09-27-initial-acknowledgement-ordering.md)
reproduces and fixes an early-reply ordering defect and records a passing full
normal recovery journey on its new source pin. The failed candidate above
remains historical evidence of the investigation.

Trace the second-session initial screen receipt, including overlapping decoder
callbacks while the first acknowledgement is being sent. Preserve strict frame
and generation checks and demonstrate the failure before correcting its owner.
Then rerun the complete normal recovery journey. Physical-device, paired LAN,
installed Mac GUI/TCC, native App/Window capture, viewport bitrate and current
source assembly remain separate open requirements.
