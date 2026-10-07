# Terminal app switching and top-row clipping

## Confirmed causes

The Terminal view called `background()` on `willResignActive`, and that method
unconditionally stopped an established SSH connection. Independently, the PTY
output callback threw `CancellationError` whenever the app was inactive. Removing
just one shutdown path would still have closed the shell.

SwiftTerm uses a scroll view with content measured in whole terminal cells. The
viewport height could end partway through a cell, so following live output clamped
the scroll offset into a partial first row. The new regression failed before the
fix at three keyboard states, with offset remainders of 14, 3 and 9 points and no
eight-point gap below the status safe area.

## Behavior

- An established SSH connection retains its channel and PTY during brief app
  switches. Transport reads pause, armed modifiers clear, and inactive/locked
  input is rejected. Foreground and app-unlock events resume the same shell,
  flush any in-flight output in order and apply the latest terminal size.
- Repeated inactive/active/inactive transitions invalidate a pending resume.
  Stopping or ending a session also invalidates pending lifecycle and input work.
- In-flight output is held in memory only, up to 1 MiB. Overflow ends the session
  with an actionable explanation; bytes are never silently discarded or written
  to diagnostics. There is no automatic new SSH connection or input replay.
- Pending login, trust or key setup still cancels on inactivity. Host verification,
  per-Mac credentials and app-unlock requirements remain enforced.
- The existing default-on, opt-out Live Activity now supports Terminal. It shows
  the Mac name, terminal symbol, paused shell-retention status, Resume and End.
  Resume routes to Terminal and preserves an already presented session. End acts
  only on its owning activity. Old activities without a service kind still route
  to Desktop. Links contain only a saved-Mac UUID and service route.
- Terminal starts eight points below the safe-area boundary and uses a viewport
  containing a whole number of rows. Both the first scrollback row and the latest
  output remain reachable, with the keyboard open or closed. Status, canvas and
  keyboard retain the selected terminal palette.

Dynamic Island is status UI, not a background-network entitlement. A bounded UIKit
background assertion completes read-pause/status work, ending on completion,
expiration or a one-second deadline. No idle assertion, keepalive timer, audio or
VoIP workaround runs. iOS may suspend execution during longer absences, and the
remote server or network may close the socket. In that case a new shell requires
an explicit user action. See Apple's
[background execution guidance](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
and [Live Activities guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

The normative direct-client specification and indexed golden fixture were updated
with lifecycle bounds and Terminal Resume URLs. The fixture manifest contains the
new canonical hash. No Mac helper or server installation was introduced.

## Verification

- Stable Xcode 27.0 (27A266a), `bash scripts/validate.sh`: passes.
- Hosted Simulator checks: 36 passed, zero failed or skipped. Includes an actual
  in-process SSH server, four pause/resume cycles with one authentication, read
  backpressure, blocked background input, ordered pending-output delivery,
  deferred resize, rapid transition races, trust cancellation, status opt-out,
  actual Terminal End intent delivery, Desktop compatibility and row geometry.
- Final paused Island layout check: passes at widths 280, 320 and 368, with large,
  xxxLarge and accessibility text, for both Desktop and Terminal. Its paused
  caption and actions were inspected in exported images.
- Eight fresh synthetic full-system Simulator screenshots were captured. Light
  and dark terminal screenshots show a complete first row below the status bar;
  the controls, menu and software keyboard remain separate from output.
- The final normal iPhoneOS app and extension compile. All 577 source/dependency
  inputs match the build report. Development signing verifies existing app/widget
  bundle IDs, private Keychain groups, provisioning and strict deep signatures.

Local evidence stays outside Git:

- `/private/tmp/maccompanion-terminal-top-boundary-before-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-repeat-switch-race-fixed-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-lifecycle-final-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-island-paused-final-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-lifecycle-20261007-captures/`
- `/private/tmp/maccompanion-terminal-lifecycle-validation-final-20261007.log`
- `/private/tmp/maccompanion-terminal-lifecycle-final-20261007-device/build-report.json`
- `/private/tmp/maccompanion-terminal-lifecycle-final-20261007-signed/report.json`

Physical installation and acceptance are recorded separately below. The user
subsequently requested a local commit of the completed follow-ups. No push or
TestFlight publication is requested for this checkpoint.

## Physical delivery

Local development **1.0 (8)** is installed and launched on iPhone 18 Pro Max.
CoreDevice confirms installation sequence **9056** and reads back version 1.0,
build 8 for the existing `media.jenny.maccompanion.ios` bundle. The installation
preserves the existing application and private Keychain identities. Physical
acceptance was pending immediately after installation; Simulator checks and
installation alone did not establish it.

Subsequently the user confirmed quick app switching works on the physical
device. They clarified that scrollback should move behind the status icons;
the safe-area-pinned layout above is superseded by
[`terminal-immersive-scrolling-20261007.md`](terminal-immersive-scrolling-20261007.md).
