# Native window and repeated view replacement repair

Date: 2026-10-02 local. This follows the
[compact session interface](2026-10-02-compact-remote-session-ui.md).
The user reports that selecting a Window stops Control and changing Shared
Display can leave a blank screen.

## Diagnosis

The installed iPhone's bounded content-free diagnostics and the installed Agent's
matching host events expose two failed replacements:

- At 18:38:31 a second surface choice arrives while replacement native enrollment
  is still preparing. Its exact ordered reset reaches the host after preparation
  retires, but the runtime rejects it with `surfaceNotAcknowledged`. The input
  route then closes and Control terminates. The release-only exception covered
  a revoked posting authorization but omitted preparation before one exists.
- At 18:38:44 a replacement reaches acknowledged capture and native enrollment,
  then the menu's backend prepare returns `unavailable`. Inspection finds that
  native preparation requires a Window's physical display to equal the Desktop
  lease's display, although the committed Window filter and measured backing
  scale support a window on another display. The user cannot identify which
  monitor held the failing window, so that specific physical attempt is not
  attributed conclusively to the cross-display guard.

## Changes

Normative specifications and the sole manifest-indexed fixtures precede both
runtime changes. Wire messages, cryptographic vectors, pairing and independent
Observe/Act/Control grants are unchanged.

An exact current reset now drains release state when native input is paused and
its posting authorization is absent or revoked. Lease, epoch, surface, coordinate,
focus, expiry and sequence checks still apply. Duplicate exact reset is
idempotent, no remote input is posted, and the pause remains in place.

The native backend retains the lease display mapping separately from the actual
Window capture display. Both the unchanged lease mapping and exact selected
window/process/bounds/scale remain checked during preparation, health and input.
Desktop and Application crop retain their existing selected-display behavior;
a moved, resized or replaced Window still requires a fresh selection.

The normal-app test runner can now place its changing disposable AppKit Window
on another physical display. Private readiness facts prove that placement before
the existing normal display/window/input/Stop journey runs. This closes a gap in
the earlier test, which placed the test window on the main display.

## Verification and installation

- Both new regressions fail against the old behavior and pass after the repair.
  Nine indexed routing cases cover cross-display Window acceptance and invalid
  Desktop/Application/absent-display denial. The reset cases cover absent and
  revoked authorization, stale binding denial, idempotent release and continued
  input pause. The older pause test retains denial of all input effects.
- Full `bash scripts/validate.sh` passes with 118 fixtures on stable Xcode 27.0
  (`27A266a`).
- Both native client SDKs rebuild for source input SHA-256
  `d82704d190cf0f0147b34dfb077f29a47d84e64f9fadc22019c6eeba99019ae8`;
  all 12 embedded lifecycle tests pass. Normal Simulator, normal iPhone and normal
  Mac/Agent builds pass.
- Signed staging verifies the Mac's existing Agent entitlements and unchanged
  119-file Sunshine catalog. The iPhone update preserves its existing signed
  application/Keychain entitlements and supports the verified physical phone.

- The expanded normal-app Simulator journey passes both Shared Display
  replacements, the selected Window on the other physical display, keyboard/
  pointer/modifier/shortcut delivery, Stop/start and cleanup, with five fresh
  native presentations. Test keys are deleted, the owned host/target retire, and
  the original Simulator app/data are restored.

The signed normal Mac update is installed at
`/Users/yihong/Applications/Mac Companion.app` and its existing Agent service is
restarted. Full installed signature, exact Agent entitlements and unchanged
bundled host files are verified. Its listening socket is present, and saved-pair
authentication succeeds after the phone update launches. The previous app is recoverable at
`/private/tmp/maccompanion-mac-pre-view-blank-fix-20261002.app`.

The signed normal update is installed and launched on the freshly verified
iPhone 18 Pro Max. CoreDevice confirms the normal app is installed. Existing app
data and pairing are retained. Signed executable SHA-256:
`df0033b0249c5b173adbff18f9886462775f362bfc034bf1ad7159f3a41fb52a`.

Physical confirmation of this repair remains pending; the user has been asked to
retry both display directions and a Window on either monitor. Simulator consent
and final input effects are substituted and do not establish physical acceptance.
Everyday recovery/elapsed acceptance and production distribution gates remain
open. The earlier frozen corresponding-source archive predates this repair.

## Private evidence

Device identifiers, screenshots, profiles, runtime stores and input content stay
outside the repository:

- Phone runtime trace: `/private/tmp/maccompanion-view-blank-iphone18-runtime-20261002.log`.
- Matched host events: `/private/tmp/maccompanion-view-blank-host-terminal-20261002.log`.
- Before/after regressions: `/private/tmp/maccompanion-view-blank-regressions-before-20261002.log` and `/private/tmp/maccompanion-view-blank-regressions-after-20261002.log`.
- Full validation: `/private/tmp/maccompanion-view-blank-validation-20261002.log`.
- Native inventory and lifecycle tests: `/private/tmp/maccompanion-native-view-blank-fixed-20261002/native-video-candidate-inventory.json` and `logs/embedded-lifecycle-tests.log`.
- Expanded normal journey: `/private/tmp/maccompanion-native-view-blank-fixed-journey-20261002/report.json`.
- Mac staging: `/private/tmp/maccompanion-mac-view-blank-stage-20261002.json`.
- Verified Mac installation: `/private/tmp/maccompanion-mac-view-blank-installed-20261002.json`.
- Installed listener and closed post-install event codes: `/private/tmp/maccompanion-view-blank-mac-listener-20261002.log` and `/private/tmp/maccompanion-view-blank-mac-postinstall-events-20261002.json`.
- iPhone signature verification: `/private/tmp/maccompanion-view-blank-iphone18-signature-20261002.json`.
- iPhone installation, launch and installed-app readback: `/private/tmp/maccompanion-view-blank-iphone18-install-20261002.json`, `/private/tmp/maccompanion-view-blank-iphone18-launch-20261002.json`, and `/private/tmp/maccompanion-view-blank-iphone18-installed-app-20261002.json`.
