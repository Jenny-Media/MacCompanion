# Input, native view switching, Finder and resize recovery

## Diagnosis

The installed content-free logs show successful replacements taking several
seconds while the old renderer drains and the new native connection enrolls,
launches and acknowledges a fresh presentation. That handover pauses input.
The old UIKit input relay additionally launched an independent task for every
gesture, allowing pending work to outlive its surface fence.

At 20:54:12 and 20:54:42 local time, surface selection and acknowledgement
succeeded, but native backend preparation failed with `unavailable` before
native enrollment completed. Finder owns desktop/background windows that the
ScreenCaptureKit catalog excludes; the two live application crop checks had
included those CoreGraphics windows. This is a concrete mismatch that could
reject Finder's admitted application crop. The affected Finder selection still
needs physical rechecking against the updated installed pair.

At 20:54:57, the host retained the original deadline and permit while the
selected capture became noncurrent. The managed host reported selected capture
context error 12. Resizing changes the admitted bounds: retaining input against
those old bounds would be unsafe. The previous health error also invalidated the
local endpoint instead of reporting that this exact native backend had retired.

## Changes

- One bounded UIKit input dispatcher serializes unsequenced gestures. Only
  adjacent pending absolute cursor positions coalesce. Buttons, keys, modifiers
  and text preserve order. Dispatch is paced below the existing limits; a view
  transition discards pending old geometry and joins already issued dispatch.
- An opaque replacement boundary remains from the old owner's drain through
  the next valid native frame. Bootstrap media cannot briefly show between
  native owners. Input still waits for the host presentation acknowledgement.
- Application resolution and both Swift/Objective-C live crop checks agree on
  on-screen, nonempty layer-zero windows owned by the selected process. Three
  cases in the authoritative fixture cover Finder backgrounds and overlays.
- Exact retired backend health returns only an inactive receipt after drain.
  Complete binding tombstones are bounded to 64. Unknown or mismatched health
  remains unavailable; an old health request cannot retire a fresh backend.
- After an acknowledged App/Window stream loses its native connection or
  enrollment, the foreground client can make one Desktop recovery attempt.
  It first checks that primary Control remains current and within the original
  deadline. Recovery fences input, drains the old native owner, and requires
  fresh Desktop video and acknowledgement. Stop, background, expired Control
  or primary revocation prevents recovery. The UI explains the transition.
- The upper UIKit selection guard now accepts the already specified Desktop
  fallback when an App/Window disappears during selection.
- The disposable normal-app QA runner waits for actual owned Agent loopback
  readiness before sending its pairing command.

Resize recovery deliberately returns to Desktop. Continuous capture of the
same window while its bounds change is a separate geometry reconfiguration
feature. Native view switching still starts a fresh connection; this change
addresses queued input and presentation flashes, and does not claim a measured
reduction in native connection setup time.

## Verification

Stable Xcode 27.0, build 27A266a:

- Eight focused regression tests pass: input ordering/coalescing, transition
  fencing, queue overflow, recovery authority/deadline restrictions, Finder
  crops, inactive retired health, health during drain, and bad capture evidence.
- Fourteen Simulator renderer lifecycle tests pass, including valid replacement
  reveal, invalid frame coverage, Stop, revocation and original expiry.
- Required `bash scripts/validate.sh` passes: 118 indexed JSON fixtures,
  repository policy checks, package/platform checks and native selected-capture
  tests. Native crop tests consume the same three indexed cases as Swift.
- Both normal iOS SDK builds pass with matching source input SHA-256
  `13cf0ede37486365301e838e8622bb5535e3eaecb77853c3377fee4a384ea7af`.
- Normal Mac and Agent build pass. The source-built native host package is
  verified, signed and catalog-pinned; all 119 host files match. Mac Agent
  entitlements and iPhone entitlements/profile are preserved.

The first live journey paired and displayed native video, then failed during
its first display replacement before reaching the Window resize. Native
preparation failed with an `NSError` while the retained-log writer reported
`No space left on device`. It is not a resize recovery pass. Host cleanup,
client-key cleanup and original Simulator state restoration succeeded.
Fourteen completed disposable `native-package/.build` caches were removed only
after checking no files were open; 8.98 GiB was recovered while evidence parents,
source and app artifacts were preserved. The repeated live journey passes with six native presentations: initial
Desktop, both display switches, selected Window, automatic Desktop after resize,
and a second Control session. It delivers keyboard, modifier, shortcut and
pointer events after recovery, Stops both sessions cleanly, preserves the signed
local endpoint, and verifies client-key cleanup, host cleanup and original
Simulator restoration. Its legacy report flags for keyboard/shortcut coverage
remain false for this new resize variant even though the XCTest executes and
passes those assertions; the runner now includes automatic recovery in those
coverage flags for future reports.

A second normal-app live journey closes the owned Window after its picker row
appears and before selection. It accepts a fresh Desktop fallback instead of
leaving Control. It passes five native presentations, both display switches,
keyboard, modifiers, shortcuts, pointer delivery, two Stop/start cycles and all
cleanup/restoration checks.

## Installation

The normal Mac app is updated in place at
`/Users/yihong/Applications/Mac Companion.app`. Its verified containing signature,
119-file host catalog and executable hashes match the stage. The existing Agent
service is reused and restarted; pairing/data and Agent entitlements are
preserved. The previous app is recoverable at
`/private/tmp/maccompanion-mac-pre-switch-resize-20261002.app`.

The signed normal iOS app is installed in place on the verified iPhone 18 Pro Max.
The existing application identifier, profile and signed entitlements are retained;
no pairing reset is performed. Device inventory confirms the installed bundle.
The first launch attempt lost its CoreDevice connection; the bounded retry
reached the device but iOS denied launch because the iPhone was locked. It must
be unlocked and opened by the user for physical acceptance.
Physical Finder selection, repeated resize and
perceived cursor latency still require acceptance on this updated pair.

Native source input SHA-256 is unchanged across the component and normal builds.
The current source-input archive has not been refreshed; external distribution
and production release acceptance remain open. Simulator component tests do not prove physical playback, actual Mac
input, measured latency or production release acceptance.

## Private evidence

Content-free logs, code signatures, provisioning material and UI attachments
remain outside Git under `/private/tmp`. Relevant roots:

- `maccompanion-switch-input-resize-host-events-20261002.log`
- `maccompanion-switch-input-resize-iphone18-runtime-20261002.log`
- `maccompanion-switch-resize-focused-v3-20261002.log`
- `maccompanion-switch-resize-handoff-stable-validation-20261002.log`
- `maccompanion-switch-resize-handoff-final-stable-validation-20261002.log`
- `maccompanion-native-switch-resize-20261002`
- `maccompanion-switch-resize-native-host-build-20261002`
- `maccompanion-switch-resize-native-host-package-20261002`
- `maccompanion-switch-resize-signed-host-20261002`
- `maccompanion-normal-resize-desktop-recovery-qa-20261002`
- `maccompanion-normal-resize-desktop-recovery-qa-v2-20261002`
- `maccompanion-normal-picker-disappearance-recovery-qa-20261002`
- `maccompanion-mac-switch-resize-installed-20261002.json`
- `maccompanion-switch-resize-iphone18-install-20261002.json`
- `maccompanion-switch-resize-cache-prune-20261002.json`
