# Normal iOS native background and connection recovery

## Verified journey and limits

The normal admitted Debug Simulator app completes pairing and saved-route
reopening, then runs three separately granted native Desktop sessions against an
isolated signed Agent and archive-rebuilt Sunshine package. Keyboard, pointer,
Shift+Tab and Copy each increase the final host input counter.

The first session backgrounds the actual app with the Home action while its
software keyboard is visible. Returning dismisses the keyboard, fences pointer
input and preserves the native presentation count. Stop retires host capture and
drains the runtime; starting again requires an explicit Control request.

During the second session, the disposable signed menu closes its own primary
network admission and drains its connections using the existing local updater
quiescence API. The normal app shows Reconnect, dismisses its keyboard and
retires its live view. Host capture stops, the runtime becomes idle, and input
does not advance. Reopening that same test listener and tapping Reconnect
preserves the saved pair, authenticates and reads live status. It does not
automatically start Control. A third explicit request presents native video,
delivers controls and stops cleanly.

This proves host-induced primary connection loss and recovery on the dedicated
Simulator. It does not prove physical Wi-Fi roaming, LAN recovery, hardware
biometry, installed Mac GUI/TCC or physical input. Mac consent is substituted in
a separate test process; final input uses the synthetic sink. No installed Mac
product, physical phone or system network/privacy setting is changed.

## Failures retained and diagnostic change

- Combined run v1 failed because the test consent bridge required the listener
  to remain listening after deliberately closing it. The bridge now admits its
  deliberately closed state for signed status readback and reopen. Production
  authentication, pairing and wire behavior are unchanged.
- Combined run v2 failed after backgrounding and Stop, before the connection-loss
  step. Mac Status showed Waiting for status and a Command did not complete
  alert. The underlying error was not recorded by the workspace callback.
- The normal workspace now records a bounded, content-free fixed event code and
  error type before forwarding that command failure. No alert is suppressed and
  no test dismisses the error to force a pass. V3 and V4 pass, but the intermittent
  v2 failure remains unexplained; a passing retry is not a root-cause fix.
- The subsequent guidance candidate projects the native owner's retired state
  to the normal live UI. It shows Remote Control needs to restart with explicit
  Stop/request instructions, blocks surface hit testing and unavailable controls,
  dismisses keyboard/composer/display sheets, and preserves the top Stop action.
  The callback is fenced to the current local product generation. It does not
  restore video or input authority and adds no wire or authorization behavior.

## Evidence

Stable Xcode 27.0, iOS 27.0, owned Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

- Dedicated background journey: one passed UI test, 96.637 seconds; exact-key
  cleanup passes, 0.053 seconds. Two native presentations, host cleanup and
  original app/data restoration verified.
- Combined v3: one passed UI test, 120.967 seconds; exact-key cleanup passes,
  0.048 seconds. Three native presentations, background fencing, explicit
  restart and primary connection recovery verified. Host cleanup and original
  Simulator app/data restoration verified.
- Same-candidate repeat v4: one passed UI test, 119.373 seconds; exact-key cleanup
  passes, 0.046 seconds. The same three-session recovery checks and cleanup pass.
- Both native SDK and normal app builds pass. The device SDK build is unsigned
  and uninstalled. Stable `bash scripts/validate.sh` passes, including 110
  indexed fixtures.

Private reports and result bundles must not be committed:

- `/private/tmp/maccompanion-normal-native-background-20260927-v1/report.json`,
  SHA-256 `dd29888e37305895ffd64628957ec1d86ddb1e05e6b30589b3f37016b168777b`.
- `/private/tmp/maccompanion-normal-native-recovery-20260927-v3/report.json`,
  SHA-256 `975bcde6c1524254e9c2d79df148514b2d30cf44ee6b7f8ce3d66778b0e2683d`.
- `/private/tmp/maccompanion-normal-native-recovery-20260927-v4/report.json`,
  SHA-256 `4f5882286d7644dee20671595857c9921a9e96b2e07385171d5214da03e37e29`.
- Combined failed v1/v2 reports and private result bundles remain in their own
  directories with their original source pins.
- `/private/tmp/maccompanion-command-diagnostics-validation-20260927.log`.

V3 normal source-input SHA-256:
`e9666207c341a917df1dc30e0487784a371b4d8e096d3aa7be58a88e89e9b2c5`.
Tested normal executable SHA-256:
`f41db694b697dfdfe5a9b7614c5337ea2a85e77636bdb460c91988d309c3c4dc`.
Disposable host source SHA-256:
`ff6f54f1e548960629315c231a8b2933cc21c68e0e0c99e1871fa4453aeae80d`.
Verified host manifest SHA-256:
`1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`.
The report also binds framework binaries and UI/cleanup/runner inputs.

## Final foreground guidance candidate

The complete recovery journey also passes on the updated normal UI, with an
explicit assertion that the restart message appears after foreground return
and keyboard input is unavailable. Stop and the subsequent fresh sessions pass.

- One UI test passes, zero failures, 121.729 seconds; exact-key cleanup passes,
  zero failures, 0.021 seconds. Three native presentations and host cleanup are
  verified, and the original owned Simulator app/data are restored.
- Both SDK builds pass and remain development-only. Stable required validation
  passes, including 110 indexed fixtures, and `git diff --check` passes.
- Private report:
  `/private/tmp/maccompanion-normal-native-recovery-guidance-20260927-v1/report.json`,
  SHA-256 `c133fbe9e30faf577364fdbb14d158c05f47d040f83f9ed6ae2885c17f0e2119`.
- Normal source-input SHA-256:
  `0963fe4546f0c18048799eecb1d6a0839f135cc26799bd0e7e0f85d4a1ca5e8d`.
- Tested normal executable SHA-256:
  `fe38e5708b747ae105381d05d2e22377fed2b9c11cff775b0a6795402c36198c`.
- Disposable host source SHA-256:
  `5e680548c9a305629f86a32046d684e32458beec9792d7dc2fbfc5721c7c429d`.
- Validation record:
  `/private/tmp/maccompanion-recovery-guidance-validation-20260927.log`.

The earlier command failure did not recur in this candidate either. Its root
cause remains unconfirmed; diagnostics remain enabled and none of these passing
runs establishes a fix for that earlier intermittent failure.

## Next

Investigate the intermittent post-background status command failure, then
exercise installed normal Mac GUI/TCC and
paired LAN/physical behavior. Native App/Window capture, visible-area bitrate
and current corresponding-source assembly remain open.
