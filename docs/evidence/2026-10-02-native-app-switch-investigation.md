# Physical App/Window switching investigation

Date: 2026-10-02 local. This follows the
[Window and repeated replacement repair](2026-10-02-native-window-and-replacement-repair.md).
The user reports that display switching works, while switching app interfaces
still fails. The exact selected application/window and its monitor have not yet
been identified.

## Physical trace

The installed iPhone 18 Pro Max trace contains successful replacement video and
input before the remaining failure. At 19:10:18 a new selection fences the old
renderer and enrollment. The new selection receives acknowledgement, completes
native enrollment, binds the measured route, and parses server information and
the application list. At 19:10:21 the native launch adapter reports
`native.launch.failed-invalidResponse`, then preparation retires and Control ends.

This attempt fails after enrollment, at native launch response validation. It
does not reproduce the earlier replacement reset rejection. The captured trace
does not establish the response's native status or the underlying capture/encoder
cause. Platform capture events show streams being constructed and stopped, but
cannot identify the failing guard. Raw owned child logs had already been deleted
with their operation credentials during retirement.

## Changes

The normal Simulator journey can use a static disposable AppKit target, covering
an idle interface as well as the existing animated target. Each mode passes both
display changes, selected App video/input, Stop/start and cleanup, with five
fresh native presentations. Consent and final input effects remain substituted;
these tests do not establish acceptance on the user's physical phone or app.

The managed Mac backend now reads at most the final 64 KiB of each owned child
log after child termination and before operation deletion. Only fixed capture
context/stream/sample codes and a fixed encoder-unavailable marker enter unified
logging. The reader rejects symlinks, hard links and files owned by another UID.
Raw lines, target names, identifiers, bounds, pixels, input and credentials are
not retained. Probe and normal retirement can also emit these codes, so a code
alone is not proof of the physical failure's cause.

The normative managed-host specification and four cases in the existing indexed
capture fixture precede this diagnostic implementation. The required-reason API
inventory records the two new Mac-only file inspection calls. Wire messages,
pairing, authorization and independent Observe/Act/Control grants are unchanged.

## Verification and installation

- Animated and static selected App normal Simulator journeys pass separately;
  both restore original Simulator app/data and retire their owned host/target.
- Two diagnostic tests pass, covering the four indexed vocabulary cases,
  bounded tail reads, symlink denial and hard-link denial.
- Full `bash scripts/validate.sh` passes with all 118 indexed fixtures on stable
  Xcode 27.0 (`27A266a`). The separate sandboxed privacy command could not inspect
  the Swift package graph; the complete validation outside that sandbox passes
  the privacy gate and all subsequent gates.
- The normal Mac/Agent build succeeds. Signed staging and installed readback
  verify executable hashes, the containing signature, existing Agent
  entitlements and the unchanged 119-file Sunshine package/catalog.

The diagnostic Mac update is installed at
`/Users/yihong/Applications/Mac Companion.app`. Its existing Agent service is
restarted and listens on the primary port. The previous app is recoverable at
`/private/tmp/maccompanion-mac-pre-app-switch-diagnostics-20261002.app`.
The iPhone remains on the preceding signed repair build with its existing data
and pairing; no iOS source changes are needed for these host diagnostics.

The remaining physical App/Window failure is **unresolved**. A repeat on the
installed diagnostic Mac is requested to identify the failing capture/encoder
check. Everyday acceptance and production release gates remain open. These
diagnostics do not repair native launch behavior, and the earlier corresponding
source archive predates this checkpoint.

## Private evidence

No physical device identifier, screenshot, signing material, real audit database
or typed content is committed.

- Phone trace: `/private/tmp/maccompanion-app-switch-iphone18-runtime-20261002.log`.
- Matched host events: `/private/tmp/maccompanion-app-switch-host-events-20261002.log` and `/private/tmp/maccompanion-app-switch-host-capture-events-20261002.log`.
- Animated/static App reports: `/private/tmp/maccompanion-native-app-switch-baseline-journey-20261002/report.json` and `/private/tmp/maccompanion-native-app-switch-static-baseline-journey-20261002/report.json`.
- Diagnostic tests: `/private/tmp/maccompanion-app-switch-diagnostics-tests-20261002.log`.
- Full validation: `/private/tmp/maccompanion-app-switch-diagnostics-validation-20261002.log`.
- Mac build: `/private/tmp/maccompanion-mac-app-switch-diagnostics-build-20261002.log`.
- Verified staging and installation: `/private/tmp/maccompanion-mac-app-switch-diagnostics-stage-20261002.json` and `/private/tmp/maccompanion-mac-app-switch-diagnostics-installed-20261002.json`.
- Installed listener: `/private/tmp/maccompanion-app-switch-diagnostics-installed-listener-20261002.log`.
