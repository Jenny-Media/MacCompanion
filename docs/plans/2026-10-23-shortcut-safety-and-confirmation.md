# Shortcut input safety and confirmation

Keep the existing typed, pasted, key and cancellable-wait steps. Correct the
three reviewed paths without changing SSH/RFB wire formats or authentication.

1. The VNC input owner inserts ordered cleanup barriers before and after a
   timed sequence. Its sole socket worker releases held keys, mouse buttons
   and native gestures. Pending accepted input precedes cleanup; cancellation
   retires copied sequence events and preserves cleanup. Cover real wire order.
2. Classify replies generated while the iOS terminal consumes remote output as
   emulator replies, preserving them while ordinary user input is reserved.
   Test queries through the actual terminal frontend during a timed sequence.
3. Validate the complete sequence before admission, then encode only its current
   input step against current negotiated modes. Enforce the actual cumulative
   byte budget and stop unsupported steps without replaying completed ones.
4. Store an optional Confirm Before Running setting per shortcut, default off.
   The review screen offers Don't ask again for this connection. Only Run
   accepts that choice; Cancel does not. In-memory exceptions match the shortcut
   definition and live transport identity. A new connection or changed steps
   asks again. Background/foreground and desktop/trackpad mode switches on the
   same transport preserve the exception. Advance the guarded profile format.
5. Replace the modal running sheet with a shared compact overlay above the
   controls, exposing the current step, wait countdown and Cancel while output
   stays visible. Cancel, retirement and completion remove it in every mode.

Use Xcode.app and the managed compiler workspaces. Run focused native and UI
regression suites, capture simulator evidence for immediate and confirmed runs,
connection exceptions, cancellation and terminal replies. Run scripts/validate.sh,
then build, sign and install build 152 on the iPhone 18 Pro Max and verify launch.
No PR, push, merge or TestFlight publication is included.

## Verification completed

- Xcode.app simulator and device builds match all 634 production source inputs.
- 246 native regression/compatibility tests passed, plus a focused controller
  screenshot rerun. All 13 simulator UI flows passed across the original batch
  and focused rerun after correcting automation timing and switch hit targets.
- `bash scripts/validate.sh` passed.
- Build 1.0 (152) was signed with existing identities, installed on the iPhone
  18 Pro Max, read back, launched and captured with Mac Companion visible.
- Screenshot gallery and detailed evidence remain outside Git in the local
  shortcut-safety-confirmation-20261023 evidence folders. Physical shortcut
  acceptance remains for the user's testing.

## Stalled SSH cancellation follow-up

Complete the matching sequence exactly once when canceled, independent of a
non-cancellable SSH write or predecessor. Retire the controls callback epoch
without dropping the transport tail or its bounded queue charge. A newer run
queues behind accepted input; stale tasks cannot send their suffix, clear a new
reservation, or report a second completion. Cover blocked current and preceding
writes, bounded repeated cancellation, late completion, and fresh input. The
simulator UI fixture holds a writer await while retaining a real loopback SSH
peer; verify Cancel removes the banner before release and fresh shortcuts stay
ordered after release. Validate and install development build 153.

Follow-up validation completed: 249 distinct native regression/compatibility
tests passed (248 in the broad run, plus the late-failure regression), all seven
selected simulator UI flows passed, and scripts/validate.sh passed. Both normal
builds match all 634 production inputs. Build 1.0 (153) was installed, read back,
launched, and captured with Mac Companion visible on the iPhone 18 Pro Max.
Evidence is outside Git under maccompanion-stalled-cancel-20261023. The UI stall
uses a controlled held writer with a real loopback SSH peer.

## Timed admission and native gesture ordering follow-up

Validate timed shortcuts structurally, retaining step indices instead of initial
encoded bytes in their schedule. Resolve only the current input step against
live terminal modes, retaining the 16 KiB queue reservation and enforcing the
actual cumulative byte limit before each write. Explain a size-limit stop.
Immediate shortcuts retain their compact pre-encoded path.

Separate local recognizer retirement from transport gesture retirement at a
shortcut boundary. Preserve accepted queued and copied native gesture events;
release their sent state at the socket-owner cleanup marker. Reject ordinary
recognizer callbacks while reserved without retiring that prefix. Keep fresh
input after Cancel ordered after the marker, and preserve independent lifecycle
retirement. Cover controller admission under shrinking/growing encodings, queued
scroll and copied pinch with a stalled worker, fresh gestures after Cancel,
existing lifecycle paths and simulator screenshots. Validate with Xcode.app,
update PR #46 and install the resulting development build on iPhone 18 Pro Max.
