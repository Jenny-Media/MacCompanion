# Native logical Desktop snapshot and Agent projection

## Scope

The acknowledged Desktop runtime now carries mandatory logical width, logical
height and rotation through its authenticated local snapshot into the Agent's
internal native enrollment snapshot. Encoded pixels remain distinct from logical
Mac points. The normative local snapshot specification and manifest-indexed
fixture were updated before the metadata extension and Agent projection.

Logical dimensions must be positive UInt32 values. Rotation is restricted to
0, 90, 180 or 270. Missing fields, zero/negative/oversized dimensions, unknown
rotation, unknown fields and mismatched correlation fail closed. There is no
encoded-only compatibility fallback. Renewal retains the logical dimensions,
rotation, install generation and original session deadline.

Store-bound enrollment compares the complete runtime snapshot around inert
backend construction and during authority reads. Logical size or rotation
changes during construction reject the enrollment. Neither metadata nor this
comparison changes signature, pairing, approval or operation-authentication
semantics, and neither releases the existing native host input pause.

## Verification

Stable Xcode 27.0 (`27A266a`) repository validation exited 0:
`/private/tmp/maccompanion-native-logical-projection-validation.log`.
All 105 indexed fixtures pass. Regression coverage includes all four rotations,
renewal preservation, malformed/missing geometry, Agent projection using logical
bounds distinct from encoded pixels, and changes to width, height or rotation
during suspended backend construction.

Both unsigned SDK component builds passed. All six framework binaries match the
refreshed inventory at native candidate input SHA-256:
`20a1fa9a35f19a67d21f156a5a199946ac7d60b8a95706a9025eed5364a28563`.
All fifteen Simulator component tests passed: four native engine lifecycle tests
and eleven adapter/owner/TLS tests. The inventory retains `releaseAdmitted: false`.

The refreshed signed Simulator journey passed one native journey test with zero
failures. It exercised two native video presentation/Stop/restart cycles through
normal UIKit owners, real pairing, independent Act/Control grants, the primary
channel and signed Mac XPC. It used continuous generated bootstrap media and the
normal Mac Desktop geometry provider. Observe remained available on the same
primary after Stop. Cleanup verified; native input remained disabled.

Private report:
`/private/tmp/maccompanion-agent-xpc-evidence.33by9_i_/signed-simulator-report.json`.
Its native candidate input matches the SDK inventory above. The combined app,
harness and helper source fingerprint is:
`cd1134aba1f3c717e4b96c5a3f242a4eaa109aafa53dc017ee96f8d664a98897`.

The matching signed Mac host lane passed all four stages: durable remote access
enablement, listener readiness, real client pairing, and authenticated native
enrollment/HTTPS launch with two lease renewals and Stop preserving Observe.
Cleanup verified. Its source input matches the same candidate above. This host
lane does not claim decoded frames or phone presentation; those are covered by
the separate Simulator journey.

Private host report:
`/private/tmp/maccompanion-agent-xpc-evidence.x9wpy1db/native-report.json`.

An earlier intermediate checkpoint also passed at candidate `2c2bad46…`; it is
superseded by this complete Agent projection checkpoint. Disk exhaustion caused
an earlier validation failure. A contemporaneous signing run failed before any
host cases and is not passing evidence. Only generated build intermediates/index
caches from finalized, cleanup-verified private evidence roots were removed,
recovering about 8.7 GiB. Source copies, reports, test results, built products and
worktrees were preserved. The full stable checks and both SDK builds were then
rerun successfully. A sandbox-blocked manifest evaluation and an incomplete test
fixture constructor were also corrected before the final stable pass.

## Remaining work

Logical metadata now survives the Agent projection, but it is not yet a native
presentation receipt. Trusted capture-mode dimensions and actual backend image
placement/clean aperture must agree with the inner source-content rectangle.
A correlated presentation acknowledgement must then join the current Control,
backend, display and surface generations before permitting host input. The
client must connect that admitted rectangle to its existing pointer, trackpad,
keyboard, modifier, shortcut and focus controls and disable them on loss/Stop.

The four rotation cases prove metadata preservation; they do not prove rotated
native video or input behavior. Both native input gates remain closed. Permanent
Sunshine/Moonlight target composition, dependency/source admission, TCC/process
ownership, signed normal-app installation and physical iPhone acceptance remain
open. This checkpoint does not claim the usable engine replacement is complete.
