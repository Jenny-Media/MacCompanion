# Native foreground recovery and setup latency

## Diagnosis

Normal view selection still closes the native renderer and enrollment, changes
the acknowledged surface, starts a fresh managed Sunshine process and launches
a fresh Moonlight connection. The continuity primitives in the preceding
checkpoint are not wired into this normal-app path. There is no deliberate
multi-second smoothing delay. Repeated host startup and encoder probing remain
the main source of delay.

Actual UIKit background entry correctly retired video and input, but the
product had no foreground replacement path. A temporary inactive scene could
also retire a valid native stream. A real primary connection loss left its
failed remote destination covering the workspace's Reconnect action.

The additional background-during-selection test exposed a separate failure:
the product canceled an old selection correctly, but the UI coordinator treated
that CancellationError as fatal and ended the current Control session.

## Changes

- Actual background still immediately fences native input and retires the old
  video generation. One foreground Desktop replacement may enroll afresh only
  under the exact original, still-current primary and Control binding and its
  unchanged expiry. The existing primary background grace remains ten seconds.
  Old renderer, enrollment, preparation and pending surface-selection work join
  before recovery. Fresh bootstrap and native presentation receipts precede
  input. Stop, another background entry, expiry, revocation or changed primary
  cancels the attempt. Failed recovery does not retry in a loop.
- Current Control observation survives native cancellation without retaining
  native or input authority. It rechecks the accepted session, primary identity,
  revisions and original deadline. Existing wire messages and golden signatures
  are unchanged. The normative lifecycle and sole indexed fixture corpus record
  the recovery rules before admission behavior changes.
- Temporary inactive scenes disable local input while retaining current video.
  An active return rechecks binding, expiry, renderer and receipt before input.
- A locally canceled surface selection preserves its current Control product.
  Genuine failures retain existing retirement behavior. A terminated primary
  closes the local remote destination and exposes workspace recovery.
- Certificate commands await process termination instead of blocking the Mac
  main actor with Process.waitUntilExit. Retirement cancels and joins an owned
  helper before removing private material. All certificate checks remain.
- The replacement client generates inert TLS identity material while the old
  stream drains and the replacement bootstrap is acknowledged. No socket or
  enrollment starts early; unused material is joined and erased on close.

## Measured limits

Ten inert-command trials on this Mac averaged 66.95 ms with waitUntilExit and
1.85 ms with termination callbacks. The host's certificate work now yields to
Stop and lease checks. Actual certificate generation remains variable.

The normal Simulator view journey passes two display replacements and one
selected Window replacement. From local input fencing to fresh native input
admission, the measured times are 2.280 s, 2.185 s and 3.115 s. These are three
local samples, not a physical latency benchmark or a statistically controlled
before/after comparison. Draining takes roughly 0.27–0.34 s; target/bootstrap
acknowledgement takes 0.21–0.32 s; fresh native preparation, launch and
presentation account for the rest. Host activation alone is about 0.85–1.1 s
in the observed runs, with repeated encoder probing.

The final foreground journey measures fresh input admission 1.564 s, 1.593 s
and 1.496 s after foreground recovery starts, including the held-selection
case. Time spent in the background and awaiting old work before that start is
excluded. These remain Simulator measurements.

Switching still reconnects native video. Complete retained-connection
integration, host-produced surface epochs, same-window resize reconfiguration
and All Displays remain open. Short foreground recovery returns to Desktop;
after primary grace or Control expiry, ordinary explicit Control approval is
required. No lost command or input is replayed.

## Verification

Stable Xcode 27.0, build 27A266a:

- Required final `bash scripts/validate.sh` passes with all 120 indexed fixtures,
  repository policy, package/platform compilation and native capture/epoch
  checks after the final source edits and live-journey cleanup.
- Ten indexed foreground-recovery interleavings and the existing golden primary
  flows pass. The primary tests verify current Control observation after native
  cancellation while native authority remains unavailable.
- The suspended-certificate-helper regression passes with concurrent retirement
  and preparation cancellation; it produces no certificate, listener or capture.
- All six real UIKit coordinator tests pass on Simulator, including both new
  selection-cancellation parameter cases and genuine failure retirement.
- Twenty-two native component/renderer lifecycle tests pass earlier in this
  checkpoint. Subsequent edits affect the normal product and coordinator; the
  final normal-app journey verifies those integration paths separately.
- Final normal Mac/Agent and Simulator/device iOS builds pass. Both final iOS
  builds share source input SHA-256
  `bb2ecf3afd4a7b60b86ccf44039f4d78e9324f68109837c07425f7c2ec6b6126`.
- The final foreground journey passes six fresh native presentations: three
  explicit Control starts and three foreground recoveries. Two ordinary Home
  returns and a Home entry while the host deliberately holds a surface
  selection all resume fresh video and input. It verifies background input
  fencing, hidden keyboard, synthetic pointer/keyboard/modifier/shortcut
  delivery, real primary loss, workspace Reconnect, explicit Control restart,
  clean Stop, client-key cleanup, host cleanup and restored Simulator state.
- A separate preceding normal-app view journey passes five presentations, both
  display switches, real target selection, selected Window input and cleanup.
  Its product differs only by the later background/selection cancellation fix.

These journeys use the normal iOS source root, live TLS, a disposable signed
host, substituted Mac consent and synthetic final input. They do not prove
physical iPhone acceptance, actual Mac event posting or production readiness.
The earlier failing journeys are retained: an input baseline raced a pending
pre-background release; a real disconnect hid Reconnect; the new test initially
checked its latch before selection arrived; the corrected latch then exposed
the coordinator cancellation bug. Every failed run verified cleanup and
restoration; none is reported as an acceptance pass.

## Installation

The normal Mac app is updated in place at
`/Users/yihong/Applications/Mac Companion.app`. The existing Agent service is
reused and listening on its existing port. Its signed entitlements and all 119
files in the existing pinned Sunshine catalog match the verified stage. The
previous app is recoverable at
`/private/tmp/maccompanion-mac-pre-foreground-recovery-20261003.app`.

The normal iOS candidate is signed, installed in place and successfully launched
on the verified physical iPhone 18 Pro Max. Device inventory confirms the app.
Existing application identity, signed entitlements and provisioning profile
are preserved. No app uninstall or pairing reset occurs.

Installed signed executable SHA-256 values:

- Mac menu: `97ac0101a94dcf0b3d17046b9a1b2d4a1b26df03fc086fd7ea284cbf6ddc597c`
- Agent: `79ac4b5cbfccfede1b545da1b00c60b1ef3bd46e7fca70cb7924f016340e2037`
- iPhone: `07b75ec0d3ad300e00b2c599cafb85556f30935fb74de294494aa30edbc83d80`

Physical acceptance of foreground recovery and perceived switching latency is
still pending. Updated corresponding-source distribution closure, retained
connection integration, everyday acceptance and production gates remain open.

## Private evidence

Artifacts, UI attachments, signing material and content-free diagnostics remain
outside Git under `/private/tmp`:

- `maccompanion-process-wait-timing-20261003.swift`
- `maccompanion-foreground-critical-tests-20261003.log`
- `maccompanion-foreground-handoff-stable-validation-20261003.log`
- `maccompanion-foreground-coordinator-tests-20261003`
- `maccompanion-native-foreground-recovery-20261003`
- `maccompanion-normal-foreground-recovery-qa-v3-20261003`
- `maccompanion-normal-foreground-recovery-qa-v4-20261003`
- `maccompanion-normal-foreground-recovery-qa-v5-20261003`
- `maccompanion-normal-foreground-recovery-qa-v6-20261003`
- `maccompanion-normal-switch-latency-qa-20261003`
- `maccompanion-mac-foreground-final-build-20261003.log`
- `maccompanion-foreground-mac-stage-v5-20261003.json`
- `maccompanion-foreground-iphone18-signature-v5-20261003.json`
- `maccompanion-foreground-mac-installed-20261003.json`
- `maccompanion-foreground-iphone18-install-20261003.json`
- `maccompanion-foreground-iphone18-launch-20261003.json`
- `maccompanion-foreground-iphone18-installed-apps-20261003.json`
