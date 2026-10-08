# Direct session recovery and optional Live Activity

## Scope and diagnosis

The user authorized reliable background recovery and an optional Dynamic Island
session status. The existing direct client called `stopViewer` on background,
cleared its viewport and closed RFB; every return required an ARD handshake.
The direct iOS client still uses only built-in macOS Screen Sharing. No Mac app,
helper, application pairing, new authentication scheme, APNs or vendor service
is introduced. Permanent release identities/dependency/signing admission remain
gated; the extension is included in the generated normal development build.

## Implementation

- On resigning active, cancel queued input, clear modifiers/cursor and release
  every sent key/button. A bounded in-flight read can finish first. The established
  native owner then sleeps on a semaphore, retaining its socket. It does not poll,
  decode, request further frames or send input while paused.
- A UIKit background task finishes input release and the paused status update.
  It ends immediately on completion; expiration or a one-second completion
  deadline retires a stalled owner. There is no background execution mode or
  persistent idle assertion.
- Foreground requests a complete framebuffer on the retained owner. Input stays
  blocked until a frame arrives. Socket failure or a 1500-ms resume deadline
  triggers one replacement attempt after the preceding owner retires. Explicit
  Done never restarts. Pause/resume generations reject pre-pause frames/status.
- A replacement preserves mouse mode, selected display ID, relative zoom and
  viewport center only when dimensions/layout are valid. Changed/missing display
  metadata falls back to All Displays and fit. Healthy resume keeps the view.
- “Show session in Dynamic Island” defaults on in My Macs > Session Settings.
  The setting persists locally and does not affect recovery. The ActivityKit
  extension shows Connected, Paused or Reconnecting; stale state offers return
  without claiming a live socket. Done, opt-out and terminal failure end status.
  Dismissal is respected until deliberate opt-in or a new viewer. A bounded URL
  opens only an existing saved Mac; an open viewer cannot spawn a second session.
- ActivityKit receives only a saved Mac UUID, user-assigned name and phase.
  The extension has no credential Keychain group or network/remote input code.
  Three fixed numeric diagnostics count pauses, retained resumes and resume
  frames; no login, endpoint, framebuffer or typed content is recorded.

## Verification

Stable toolchain: `/Applications/Xcode.app`, Xcode 27.0.

- Required `bash scripts/validate.sh`: exit 0, private output
  `/private/tmp/maccompanion-session-recovery-validation-20261004.log`.
- Hosted native/Swift tests: **22 passed, 0 failed, 0 skipped**.
  `/private/tmp/maccompanion-session-recovery-verified-tests-20261004.xcresult`.
  Includes an actual production native owner over a synthetic connected socket:
  sent input releases, no requests/decoding while paused, a full refresh on the
  same socket, input readiness after a frame, and Stop waking a paused owner.
  Additional coverage checks idempotent lifecycle, interrupted handshake, one
  deadline-driven replacement, stale frame rejection, preserved display/zoom/
  mode, and existing parser/viewport/cursor/security boundaries.
- Actual ActivityKit starts, updates to Paused and ends in Simulator. Its local
  content snapshot publishes asynchronously; the test awaits that publication.
  Disabled system activities, default/opt-out, foreground-only creation,
  orphan retirement, dismissal and resume-URL boundaries also pass.
- Actual Simulator UI: My Macs opens Session Settings; the toggle defaults on,
  changes off, remains off after Done/reopening, and can be restored on. Rendered
  sheet labels/spacing are readable. MCP `tap` did not activate SwiftUI buttons;
  a 150-ms touch down/up did, without changing application source.
- Normal iPhone source build and matching extension version metadata pass.
  Build output: `/private/tmp/maccompanion-session-recovery-device-20261004`.
  All application input hashes match the final source.
- Existing wildcard development profile/device validity and deep signatures
  verified. The app keeps its existing saved-login Keychain group; the extension
  has no Keychain group. Signed output:
  `/private/tmp/maccompanion-session-recovery-signed-ios-20261004`.
- Install succeeds on iPhone 18 Pro Max, database sequence 8164, preserving app
  data. `devicectl` launch succeeds. No uninstall or credential extraction occurs.

## Physical acceptance and remaining checks

The user confirms that, after the requested short background interval and return
through Dynamic Island on iPhone 18 Pro Max, the desktop resumes with display and
zoom preserved: “Resumes and settings are preserved.” This verifies the short
app-switch return and viewport behavior on the installed update.

The fixed numeric device counters corroborate connection reuse: one connection
start, two background pauses, two retained resumes and two resume frames, with
1,605 presented frames and failure stage zero. The counters were read from only
`Library/Caches/VNCDisplayDiagnostics-v1.json`; no credentials, framebuffer or
typed content was extracted.

Long background intervals, lock/process termination, input after return and
sustained reliability still require physical acceptance. iOS can still suspend
or terminate the process and the Mac can close a paused socket; indefinite
background connectivity is not guaranteed. Public release/secure transport gates
remain.

## Platform references

- [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Apple bounded background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
