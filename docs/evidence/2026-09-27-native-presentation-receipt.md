# Correlated native presentation receipt

## Scope

The normative primary-message specification and two manifest-indexed records were
updated before admitting the presentation request/receipt on the authenticated
Control primary. Observe and Act cannot send the request. Pairing, application
authentication, approval and enrollment signature bytes are unchanged; the existing
golden cryptographic vectors remain authoritative.

The request binds the enrollment fence, challenge message ID, native renderer
generation and admitted encoded dimensions. The host dispatcher reserves the
transition, joins the current durable grant and registered key, and rechecks them
after bridge work. The bridge requires its exact active primary/challenge/fence,
allows one renderer generation per enrollment and suppresses cancelled or parallel
presentation results. No replacement can inherit an old acknowledgement.

The coordinator checks runtime/durable authority and backend activity around
actual-sample inspection. Only a fresh sample for its own operation and exact
encoded size produces a receipt. It rechecks freshness after its final awaits.
Missing/stale/mismatched/future evidence or authority/backend loss retires the
attempt. The receipt carries trusted capture pixels and acknowledged runtime
logical dimensions; physical display IDs and host monotonic time stay local.

The client reserves its correlated waiter before send, requires the exact original
challenge/fence/renderer generation and checks encoded and logical dimensions
against its current acknowledged Desktop. Its enrollment and role owners check
current authority and original primary/activation before and after the handshake.
A receipt is not an input permit. Both native input gates remain closed.

## Renderer integration

Source inspection found that the pinned Moonlight `videoContentShown` callback
fires immediately after an IDR sample is enqueued and its layer is unhidden.
That callback is insufficient for this acknowledgement. The experimental engine
now separately reads the owned AVSampleBufferDisplayLayer's actual display
readiness, visible state and nonfailed status on the main thread. Apple documents
[isReadyForDisplay](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer)
as indicating that the first frame is ready for display.

The normal UIKit native owner requires the current displaying binding/generation,
exact surface, attached visible view hierarchy, positive bounds, active application
and foreground-active window scene, plus this renderer readiness check. Default
drivers report no readiness. It reserves one acknowledgement task and rechecks all
conditions after the receipt. Stop/retirement cancels the task; late completion
cannot mark another owner acknowledged. Acknowledged presentation loss retires the
owner. The injected experiment adapter forwards the acknowledgement through the
normal enrollment and role owners. The release target still supplies no adapter.

## Verification

Focused wire, coordinator, bridge and client routing tests cover closed/missing
keys and bounds, exact current sample/geometry, pending/future/stale/wrong-operation
rejection, Stop/revocation/backend loss during sample inspection, challenge binding,
renderer replacement, parallel acknowledgement, cancellation and client logical
geometry mismatch. Stable Xcode 27.0 (27A266a) full repository validation exited
0 with 108 indexed fixtures. Private log:
`/private/tmp/maccompanion-native-presentation-final-validation.log`.

Both unsigned SDK components built at the final candidate, and all six framework
binaries match the refreshed inventory (`releaseAdmitted: false`). Fifteen
Simulator component checks also passed at the preceding renderer-integration
snapshot before the host-only concurrency repair. The final candidate's host
concurrency and retirement regressions passed in full validation.

The final signed Simulator journey passed two actual visible native frame,
presentation-receipt, Stop and restart cycles with continuous bootstrap. Each
cycle required renderer readiness and the correlated receipt before Stop,
verified actual capture evidence, retained the same primary for Observe, and
kept native input disabled. One journey test passed with zero failures and
cleanup was verified. Private report:
`/private/tmp/maccompanion-agent-xpc-evidence.2ga2lidb/signed-simulator-report.json`.
Combined source/helper/harness fingerprint:
`3fdfd05e49d9ee1d6676a8d77912bc3b72255830337f98e5d213a07049ec36e3`.

A preceding retry exhausted disk space before native playback. The normal report
could not be written. The exact orphaned disposable service and private state
were recovered and their absence verified, along with removal of the Simulator's
test fixture. Private recovery evidence:
`/private/tmp/maccompanion-agent-xpc-evidence.t8u9ru23/disk-exhaustion-recovery.json`.
Generated caches from completed runs were reclaimed; their source copies,
binaries, logs and test results were preserved. Cleanup now retains the exact
PID before diagnostic writes and continues exact-job termination if a diagnostic
write raises an I/O error. A simulated ENOSPC check verified both properties;
full validation and the final live run passed after that repair.

Native source input SHA-256:
`a371435b5e1ff8643b10e26bb1efba0f26457950948c20ea4bd5a53c148831d6`.
The managed Sunshine binary remains the previously verified
`c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d`.

## Concurrent health repair

The first live integration attempt retired native playback during the new
handshake while Control/primary stayed connected. Private failed report:
`/private/tmp/maccompanion-agent-xpc-evidence.43cntf93/signed-simulator-report.json`;
cleanup was verified. A suspended-read regression then reproduced false backend
loss: the Agent proxy refused a concurrent watchdog health read while sample
inspection already owned its single pending command. The regression failed on
the preceding implementation and passed after repair.

Read-only health callers for the same exact operation now join one in-flight
command; each checks current operation/scope and retirement after the result.
Completed results are not cached. Preparation/activation remain exclusive.
Retirement fences readers before cancelling and joining their shared command;
a late active/sample response cannot escape. A separate regression checks that
retirement rule. The normative local-backend profile and indexed cases cover the
concurrency contract. This reproduced race does not establish the cause of the
older pre-native restart failure recorded in earlier checkpoints.

## Next

Join this receipt to a fresh host runtime presentation permit and revalidate the
native backend at the final input posting boundary, then connect the existing
keyboard, modifiers, shortcuts, pointer and focus controls using source-content
geometry. Permanent dependency/corresponding-source/process/TCC admission,
release composition and physical installation remain open. This checkpoint does
not change independent Observe/Act/Control grants or install either normal app.
