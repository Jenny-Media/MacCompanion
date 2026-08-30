# App-switch disconnect investigation

Scope: physical-iPhone failure after changing the Mac's focused view. Local
Xcode 27 beta evidence only; no external-beta or stable-toolchain claim.

## Observed failures and reproduced causes

The original 08:43 session installed and acknowledged Desktop successfully.
Immediately after the focused-view transition, the new encoder reported
`outputRejected`. Input/media and then the primary connection subsequently
closed. The old build did not log the rejected frame dimensions, so the exact
size of that historical frame is unavailable.

A permission-free test using this Mac's real VideoToolbox encoder reproduced
odd-size truncation: requesting 641x361 produced 640x360. The production target
catalog previously published odd dimensions unchanged, and the publisher
correctly rejected the resulting mismatch. The catalog now aligns encoded
sizes before descriptor/capture/encoder construction, retaining logical input
bounds and strict output validation. Thirty geometry cases and eight real
encoder cases cover the fix.

A separate deterministic production-scheduler regression reproduced a valid
surface change being treated as an invalid renewal: the sleeping scheduler
remembered counter 0, while the runtime had advanced through a surface lease
and renewed counter 1 to 2. Renewal now returns its exact serialized prior
lease and acknowledged command together. Fresh issuance time is sampled after
final admission; no separate pre-renewal snapshot or stale wake timestamp can
be mistaken for the actual prior lease. Original session/display/classes and
exact per-renewal fences remain checked. Tests cover multiple transitions,
delayed issuance, invalid display, counter gaps, stale revisions, wrong time,
and wrong surface.

The physical session on the first updated build at 08:57 passed the formerly
failing focused-view transition. It later received `ambiguousGeometry` with
`inputPaused=true`; input sequence 73 arrived before the client could react,
and `surfaceNotAcknowledged` tore down the connection. This directly identified
a second app-switch race, not another encoder failure.

After successful focus-pause input release, the runtime now consumes exact
reliable input ordering without any OS effect. It still validates current
lease, expiry, class, sequence, and complete focus fence; initial/replacement
surfaces without acknowledgement do not gain this behavior. Drained actions
are never replayed, and input remains closed until the normal replacement
acknowledgement. A red/green regression verifies no events are posted during
pause and only new input executes after acknowledgement.

## Evidence locations

- `/private/tmp/maccompanion-app-switch-diagnostic.log`: original session.
- `/private/tmp/maccompanion-real-encoder-dimensions.log`: real-encoder red test.
- `/private/tmp/maccompanion-app-switch-red.log`: geometry/scheduler red tests.
- `/private/tmp/maccompanion-app-switch-green.log`: geometry/encoder green tests.
- `/private/tmp/maccompanion-app-switch-renewal-final.log`: scheduler validation.
- `/private/tmp/maccompanion-app-switch-installed.log`: first updated physical
  session and exact focus-pause/input failure.
- `/private/tmp/maccompanion-focus-input-red.log` and
  `/private/tmp/maccompanion-focus-input-green.log`: focus-pause regression.
- `/private/tmp/maccompanion-feature-tests.Gu9aRN`: three successful odd-size
  real-window Simulator runs before adding the focus-pause case; pairing
  regressions also passed.

## Final validation and installation

- `scripts/validate.sh` passed on the completed source: 1,724 tests across its
  42 reported test runs, including the opt-in real encoder, policy checks and
  platform builds. Log:
  `/private/tmp/maccompanion-app-switch-complete-validation.log`.
- The expanded real-window Simulator scenario passed three times (73.730,
  74.198, 74.353 seconds), including odd sizes, repeated focused-to-focused
  pauses, post-transition input, Desktop recovery, zoom, composed/direct iOS
  keyboards, Stop and reconnect. Evidence:
  `/private/tmp/maccompanion-feature-tests.mPlAjb`.
  Its bundle-independent pairing reliability checkpoint also passed.
- The final Mac target built with the existing development identity and passed
  deep/strict signature verification. Both installed app and Agent debug
  binaries matched the build, and the replacement Agent was running. Log:
  `/private/tmp/maccompanion-focus-switch-signed-build.log`. Rollback app:
  `/private/tmp/maccompanion-focus-switch-backup.iH18Qc/Mac Companion.app`.
- No iOS binary changed. A fresh physical session on the final build at
  09:05:37 completed four focused/Desktop replacements, including both
  ambiguous-geometry and editable-focus pauses, and renewed through counters
  4, 6 and 7. The prior encoder/output and input-admission failures did not
  recur. At 09:06:01 the session revoked cleanly and the primary socket reported
  `remoteClosed`; the input lane reported `invalidInputRead` during teardown.
  Without phone-side logs or user confirmation, this does not distinguish a
  user Stop/background action from another client-side failure. It is not an
  unqualified physical end-to-end pass. Evidence:
  `/private/tmp/maccompanion-focus-switch-physical-session.log`.

The lab captures only its disposable window
and posts synthetic input only to its own process. It does not prove physical
Face ID, production pairing/TLS, AX discovery, or arbitrary-app keyboard UX.
No pairing reset, permission change, or automated Control approval was made.
