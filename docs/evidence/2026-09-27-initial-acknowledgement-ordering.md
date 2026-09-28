# Initial screen acknowledgement ordering

## Reproduced defect

The normal recovery candidate with the Observe refresh fix passed its first
session, background fencing/restart guidance, Stop and live status refresh, but
the second Control request immediately returned to the workspace. Content-free
diagnostics identified the initial render receipt path as terminal.

A deterministic test against the actual Interactive channel and primary router
then suspended the initial acknowledgement send after the transport accepted
its frame. A valid, correlated host reply arrived before that send returned.
The channel had not yet stored its awaiting-acknowledgement state, so it rejected
the reply. The six early-reply variants failed with twelve recorded issues;
the six ordinary-send variants passed. This reproduces a concrete ordering
defect. The earlier Simulator log identifies only the error type, so it does not
by itself establish the exact callback ordering in that failed run.

Private reproduction:
`/private/tmp/maccompanion-initial-ack-reentrancy-reproduction-20260927-v2.log`,
SHA-256 `5fbaafbc0f46d32714b57422804448cedd8eb09d1334ffd3646b79d8c8a9ca17`.

## Fix and invariants

The normative client composition contract and indexed local scheduling fixture
were updated before implementation. The channel stores its pending
acknowledgement state before the authenticated send can suspend. It preserves
state committed by an early host reply instead of writing an old coordinator
copy over that reply when the send finishes. Success rechecks current ownership,
invalidation and Stop state. A failed old send cannot clear a different current
descriptor.

The local activation enters awaiting-acknowledgement before sending, after the
exact clean-frame receipt has been confirmed. A concurrent receipt cannot start
another acknowledgement or rewind an activation made active by an early reply.
Post-confirmation phase revalidation also prevents an asynchronous callback from
continuing after ending or failure has won. Wrong receipts still fail closed.

No wire body, grant, pairing, approval, operation-signature or cryptographic
input changes. Existing exact frame/session/epoch/surface fences and router
correlation/replay checks remain; the committed host reply remains necessary
before input is enabled.

## Targeted tests

- Eighteen primary-channel cases pass: original approval delivery/control-life
  variants with ordinary acknowledgement delivery, early committed reply and
  primary invalidation during the suspended send. Invalidation leaves the
  channel closed without restoring an initial surface.
- Eight local activation cases pass: ordinary and overlapping renderer receipts
  across Stop/role-loss variants. Exactly one acknowledgement is sent, an early
  reply remains active after send completion, and existing input/cleanup rules
  remain enforced.
- The stable required validation lane passes, including 112 indexed fixtures.
  It runs after the final current-owner failure fence was added.

Private targeted records:

- `/private/tmp/maccompanion-initial-ack-ordering-final-tests-20260927.log`,
  SHA-256 `6159795fd3ff83524d6387c6b4cdfc7c1d8790276b136fb0b958fb5159b13ff1`.
- `/private/tmp/maccompanion-initial-render-overlap-fixed-20260927.log`,
  SHA-256 `57a163e63a8b6f7e5c5dfad743329c931492de1b60a597f978f5ea2457da3d25`.
- `/private/tmp/maccompanion-initial-ack-validation-20260927.log`.

These tests establish local scheduling and fences. The normal app's full
Simulator recovery result is recorded separately; physical phone, LAN and
installed Mac GUI/TCC behavior remain independent acceptance gates.

## Normal app recovery acceptance

The final normal iOS root passes the complete Simulator journey with this fix:
pairing, saved-route reopening, three native presentation/input-admission
sessions, keyboard, pointer, Shift+Tab, Copy, real background input fencing and
restart guidance, explicit Stop/restart, primary connection loss, Reconnect
without pairing again, and a third fresh native session. The second session
that previously closed during its initial receipt now stays active.

- One UI test passes, zero failures, 119.965 seconds.
- Exact owned pair-key cleanup passes, zero failures, 0.042 seconds.
- Three native presentations, disposable host retirement and original Simulator
  app/data restoration verified. Normal app remains stopped after restoration.
- Both native SDK/normal app builds pass. The device build is unsigned and
  uninstalled. Stable required validation with 112 fixtures and diff checks pass.

Dedicated Simulator: `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`, iOS 27.0,
stable Xcode 27.0. Human Mac consent is substituted in the separate signed test
menu. Capture is real Desktop capture, while final input uses the synthetic
sink. Primary disconnection is induced on the isolated signed loopback host;
this does not establish physical Wi-Fi roaming or paired LAN behavior.

Private report:
`/private/tmp/maccompanion-normal-initial-ack-recovery-20260927-v1/report.json`,
SHA-256 `4193117370a40579a3b5e34e4fe7ee17fae2b3943fd3c5ccbe0155545e04e617`.
Normal source-input SHA-256:
`8eb13a1f51e99faf5d308879691ef264bd7bc17139f2efa2a8b57c60b27f9583`.
Tested normal executable SHA-256:
`a4778ba791526f44a1f15c76604402881bef7dd2a2e281efe38b63779c4e4076`.
Disposable host source SHA-256:
`962df7f1102829fed64fb8d3552ce6ba759d194d78070babad86ebc81f6039bc`.
Host manifest remains the verified archive-rebuilt package:
`1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`.
The report binds UI/cleanup/runner and framework inputs as well.

## Remaining work

Native App/Window capture, viewport bitrate, current source assembly, installed
normal Mac GUI/TCC and paired LAN/physical acceptance remain open. The earlier
Observe and initial-receipt failures retain their own reports and source pins.
The new passing result establishes this candidate's recovery behavior; it does
not infer the exact callback ordering in historical failures.
