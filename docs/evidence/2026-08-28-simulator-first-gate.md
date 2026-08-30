# Simulator-first debugging gate

User direction: keep debugging and iteration on Simulator. No physical iPhone
installation, launch, interruption, or test was performed in this work. The
installed production Mac app and Agent were not replaced or restarted.

## Automated coverage added

- Three minutes of unattended real-window video: 90 seconds Desktop and 90
  seconds focused view. Check advancing rendered sequences, actual visible
  tinted pixels, at least 20 successful renewals per phase, and host/client
  error state.
- Five alternating Stop/forced-drop/reconnect cycles with the direct iOS
  keyboard open. After every close, independently query the lab host and
  require capture stopped, runtime idle, and no queued media before reconnect.
- Five actual Simulator background/return cycles through the production UIKit
  lifecycle bridge; require a fresh dial round and no terminal failures.
- Named runner profiles and static checks against physical-device targeting.

## Findings resolved in the Simulator loop

1. The initial new test tried to tap Stop behind the native composer sheet.
   It now switches to the direct keyboard and asserts the action is hittable.
   Evidence: `/private/tmp/maccompanion-feature-tests.gMUmbg`.
2. Even with the direct keyboard, the bottom toolbar's Stop was covered. The
   production SwiftUI view now also offers Stop Remote Control in its top
   More menu. It reuses the same Stop action/state and native Button/Menu
   behavior, following the SwiftUI UI-patterns guidance; no grant or transport
   logic changed. Red test: `/private/tmp/maccompanion-feature-tests.8SqPom`.
   The menu was visually inspected above the open keyboard in the Simulator
   recording, and the live test successfully invoked it.
3. The lab host could retain one queued frame after Stop: it stopped capture
   directly while the serialized runtime was still active. A pending media
   callback could enqueue after the purge. The host now invalidates runtime
   authority through the production ordered cleanup before final purge and
   transport close. Runtime-idle telemetry makes this checked, not assumed.
   Red: `/private/tmp/maccompanion-feature-tests.cjkn7y`.
   Green: `/private/tmp/maccompanion-feature-tests.jqJSHt` (five cycles,
   65.068 seconds; pairing regressions also passed).

## Validation

`scripts/validate.sh` passed on the final code: 1,724 tests across 42 reported
test runs, policy checks, and platform builds. Log:
`/private/tmp/maccompanion-simulator-first-complete-validation.log`.

The complete real-window Simulator suite passed all 10 UI tests with zero
failures in 475.448 seconds, including the 194.201-second idle soak and
64.972-second five-cycle reconnect scenario. Its separate pairing regressions
also passed. Evidence: `/private/tmp/maccompanion-feature-tests.8a4Qc2`;
runner log: `/private/tmp/maccompanion-simulator-first-final-full.log`.

Three consecutive live-feature repetitions also passed with zero failures:
`/private/tmp/maccompanion-feature-tests.SldMA4`. These cover pointer/pinch,
focused-to-focused pause/replacement, Desktop recovery, composed text, direct
iOS keyboard input, remote Return, abrupt drop, reconnect, and Stop.

Xcode beta emitted a nonfatal `simctl` diagnostics-collection warning after
the successful XCTest runs. The test results and `.xcresult` bundles were
retained; this is not stable-toolchain or release evidence. The repository
material validator and `git diff --check` also passed.

## Remaining evidence boundary

This is local Xcode 27 beta / iOS 27 Simulator evidence. The real-window lane
captures only the disposable Mac lab's own window and posts only allowlisted
synthetic input to its own PID, with existing TCC permissions. No production
Keychain, privacy prompt, pairing reset, or global input was used.

The lab seeds pairing/approval and uses loopback transport plus its own
renewal scheduler. The separate lifecycle lane uses a synthetic dialer.
Their passing results do not establish the shipping app's combined
route-to-Control lifecycle or resolve the physical app-switch report by
themselves. The next Simulator integration slice should connect those
production owners behind narrow injected transports. LAN/Bonjour/TLS,
Secure Enclave/Face ID, final signing, and device-specific behavior remain
later explicitly authorized checkpoints.
