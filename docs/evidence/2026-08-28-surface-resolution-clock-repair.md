# Automatic zoom connection and capture transition repair

Status: regression tests, full repository validation, signed Mac/iOS builds,
installation, and Agent/listener restart passed on Xcode 27 beta. The updated
physical phone authenticated successfully. Remote Control with automatic focus
still requires a fresh user-approved run of the combined Mac/iOS fixes.

The first installed clock-only fix was tested with a fresh phone approval. It
passed the former `expired` failure and exposed the separate capture transition
deadlock below. The next live run completed the Mac transition and exposed the
client handoff races below. All fixes are now installed; a successful complete
Control session with the final combined builds is not yet claimed.

## Observed failure

The installed Agent repeatedly authenticated the iPhone, accepted its Control
approval, installed the Desktop runtime, and opened both role channels. Within
about half a second, `interactive.surface.select` failed with `expired`; the
primary transport closed and iOS returned to its workspace. Reconnect itself
succeeded. This is distinct from the earlier reconnect-button/background
cancellation observation.

## Root cause and correction

Target resolution crosses authenticated local IPC. The menu app creates the
replacement descriptor after the Agent has timestamped the incoming request.
The Agent incorrectly supplied that earlier request time to descriptor
validation. `AdaptiveSurfaceAuthority` reports `expired` both for an expired
descriptor and for one whose creation time is later than the validation time.
Consequently, ordinary IPC delay rejected freshly resolved surfaces.

The Agent now samples its host monotonic clock after resolution, uses the same
sample in milliseconds and nanoseconds for preparation, and resamples after
runtime preparation to calculate remaining wire validity. Inventory responses
use the same post-await freshness rule. Clock rollback, future-created and
expired results still fail; no descriptor, execution lease, session deadline,
pairing, permission, or grant is extended or replaced.

## Follow-on capture deadlock

The clock-only build accepted the focus target and stopped the Desktop encoder,
but never returned the surface-transition receipt. Later renewal and teardown
commands queued behind the same operation. Both processes remained alive.

The runtime serialized surface transition while awaiting capture activation.
Activation awaited `publisher.transition`, which in turn awaited
`runtime.publishMedia`. That media operation was serialized behind the original
transition, creating a circular wait. Reusing the publisher also exposed the new
sequence state to delayed output from the retired capture.

The runtime now passes its last accepted media sequence to activation. Capture
creates a fresh publisher for the exact replacement fence; it does not publish
during activation. Its first clean encoder sample publishes discontinuity,
configuration, and keyframe through ordinary runtime validation. A retired
publisher retains only its old fence and cannot mutate the replacement state.
The runtime still requires the exact acknowledgement before admitting input.

## Client cross-channel handoff

The phone console reported `media pump failed error=consumerRejected` immediately
after the Mac successfully returned its surface-transition receipt. Source
inspection found that the client rejected all media in `awaitingSelection`,
including valid old-source frames still arriving while the host prepared the
replacement. Primary and media use separate connections, so either can overtake
the other at the transition boundary.

The client now continues strict old-fence admission while waiting. A primary
`selected` response can wait up to two seconds for its exact old-media boundary;
a new-surface media record can wait up to two seconds for the primary response.
Neither path decodes unconfirmed media, skips missing records, or changes the
exact boundary check. The media pump holds only its current bounded record.

The channel regression also reproduced a delayed prior-view render callback
closing the transition with `mediaBoundaryMismatch`. An exact prior-descriptor
receipt at an already-admitted sequence is now ignored during replacement;
it cannot acknowledge the new surface. All other mismatch checks remain.

## Verification

- Before the fix, new Desktop and focused-region regression cases with a
  20-millisecond resolution advance failed with `expired`.
- After the fix, all eight surface-handler tests passed, including delayed
  inventory/resolution, strict expiry/future-date rejection, clock rollback,
  sequence rejection, and exact clean-frame acknowledgement.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
  scripts/validate.sh` passed, including `git diff --check`.
- The signed Mac application and embedded Agent built successfully with the
  existing development profile. Strict nested signature verification passed;
  designated requirements and the Agent Keychain group match the prior build.
- The prior app was preserved locally for rollback. The updated containing app
  repaired its already-enabled registration, launched the replacement Agent,
  and restored the private TCP listener. No privacy prompts or Control approval
  were accepted by automation.
- After the deadlock fix, all 21 selected test functions passed: eight surface
  handler tests, 12 media publisher tests, and the serialized surface admission
  test. Parameterized replacement boundaries include zero, two, and 100 records.
- The real runtime/publisher integration test starts replacement output during
  activation, completes the transition, rejects a late old-source frame, accepts
  the exact clean-frame acknowledgement, and continues replacement output.
- Full `scripts/validate.sh` passed again after both fixes, including platform
  compilation lanes and the whitespace check. The signed containing app and
  embedded Agent were rebuilt, verified, installed, and restarted. The private
  listener is present. The existing physical iOS app was opened, not reinstalled.
- After the client fix, ten selected client test functions passed, including
  parameterized primary-first/media-first delivery, old media during selection,
  late old render callbacks, replacement clean-frame proof, and exact host ack.
  The late-render regression was observed failing before its correction.
- Full `scripts/validate.sh` passed a third time with the client fixes included.
  The iOS target built and passed strict signature verification, then was
  installed over the existing app without deleting pairing data. A fresh launch
  authenticated against the installed Agent; the phone then backgrounded before
  another Control approval. That background cancellation is not a new failure.

Validation uses Xcode 27 beta and remains provisional for the stable toolchain
lane. It does not substitute for a successful physical automatic-zoom session.
