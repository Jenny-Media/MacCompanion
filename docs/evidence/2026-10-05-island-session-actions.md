# Dynamic Island identity and session actions

## Changes

The compact island now shows the user-assigned Mac name in a bounded one-line
space beside the phase symbol. Expanded presentation shows the name and actual
phase; stale content says Paused. Expanded and Lock Screen presentations share
Resume and End Session controls. Minimal presentation retains the desktop symbol.
Long names truncate within available space and retain the full accessible name.

End Session is a non-discoverable, background-only `LiveActivityIntent`, shared
between the app and widget targets. It sends the activity's opaque unique ID to
the existing app-process viewer. Only the matching current activity can invoke
the deliberate exit path: finish its activity owner, cancel connection/recovery
work, stop/release the native viewer, retire its observers/background pause work,
and return to My Macs. A retired ID, another ID or a repeat cannot close a newer
session. With no viewer, only the matching orphaned activity is dismissed. No
connection, login read, remote command, Mac helper, APNs, polling or new background
execution assertion is introduced.

The attribute structure and existing resume URL remain unchanged. The system's
activity ID supplies the session scope rather than the saved Mac ID. Normal
in-app Exit to My Macs now shares the same deliberate exit path. Source is based
on Apple's [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
and [ActivityViewContext activity ID](https://developer.apple.com/documentation/widgetkit/activityviewcontext/activityid)
APIs, verified against the installed SDK. The normative specification and existing
indexed fixture were updated first.

## Verification

- All 50 hosted Simulator tests pass. New checks exercise the real intent perform
  path and ActivityKit backend, paused-viewer exit with a recording native owner,
  no foreground recovery afterward, repeated/unknown/retired ID handling, and
  dismissal of just one orphan while another activity remains.
- Connected, Paused, Reconnecting and stale cards are rendered at 320-point width
  with a long synthetic Mac name. Exported screenshot inspection confirms names,
  phases and both action labels fit. These are the shared widget components;
  actual system delivery from a phone's island still needs physical acceptance.
- The first aggregate run exposed an existing unauthenticated-peer test that
  fulfilled its expectation for multiple queued status callbacks. Its observer
  now consumes the first terminal callback and uses a weak session capture. The
  corrected aggregate run passes with no skipped tests. No transport policy is
  weakened. Verified result bundle:
  `/private/tmp/maccompanion-island-actions-verified-tests-20261005.xcresult`.
- Required `bash scripts/validate.sh` passes with stable Xcode at
  `/Applications/Xcode.app/Contents/Developer`. Log:
  `/private/tmp/maccompanion-island-actions-validation-20261005.log`.
- Normal device build, all 482 source input hashes, binary hash, deep signature,
  existing Keychain group, matching device profile and ActivityKit extension
  verification pass. Compiled App Intents metadata in both targets contains the
  same End Session identifier and activityID parameter, with openAppWhenRun false
  and isDiscoverable false. Private signed report:
  `/private/tmp/maccompanion-island-actions-signed-ios-20261005/report.json`.
- Installed and automatically launched on iPhone 18 Pro Max, sequence 8292,
  preserving app data. Physical compact/expanded layout and system action delivery
  remain pending. Acceptance: connect, background, expand the island, End Session;
  the island should disappear and the next app opening should show My Macs.

Synthetic screenshots/content and signing material remain outside the repository.
No commit, publication or production release is made.
