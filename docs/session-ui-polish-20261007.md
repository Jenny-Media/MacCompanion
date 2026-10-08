# Session UI polish — October 7, 2026

## Changes

- Terminal fills its safe-area background with its selected palette. Status text,
  floating controls and the number/modifier accessory match that palette, including
  a dark Terminal inside a light app. Theme changes retain the existing session.
- Desktop and Terminal use `CompanionVNCControls` for tap and press-and-slide, and
  `CompanionVNCMenu` for category navigation. Session menus share Connection Details,
  App Settings and Exit to My Macs. Terminal groups key operations under SSH Keys.
- Desktop and Terminal sign-in/progress cards are centered in the available region.
  The misleading drag handles are removed. Compact, tabletop, keyboard and large
  text layouts preserve existing text fields and session ownership.
- Short menus fit their rows, with consistent section spacing. Long menus scroll.
  Size updates are coalesced outside UIKit layout, observe actual table geometry,
  and apply only to the visible menu. UIKit adds navigation chrome to the requested
  body size; recording that request prevents repeated resizing and extra padding.
- Connected Terminal details use the same compact native dialog as Desktop.
  Setup instructions and named password-manager recommendations are removed from
  connection details. iOS AutoFill field semantics remain present.

## Verification

Stable Xcode **27.0 (27A266a)** and the dedicated iOS 27.0 Simulator were used.

- Required `bash scripts/validate.sh`: passed. Normal desktop access was necessary
  for the existing legacy test that reads `CGMainDisplayID()`; the shell sandbox
  returns no display. Final log:
  `/private/tmp/maccompanion-session-polish-validation-final-20261007.log`.
- Normal `MacCompanionIOS` Simulator build: passed.
- Hosted Simulator tests: **42 passed, zero failures** across appearance, adaptive
  layout, session controls, Terminal layout and the two focused capture tests.
  Result: `/private/tmp/maccompanion-session-polish-final-20261007.xcresult`.
- Captures cover light, dark and accessibility text sizes. A full system capture
  confirms the immersive status bar and matching keyboard in the mixed-theme case.
- App copy search found no named Passwords app or 1Password recommendations in
  current app sources. Generic password and iCloud Keychain security copy remains.

Synthetic captures and their local HTML preview are outside Git:
`/Users/yihong/.codex/visualizations/2026/09/23/01a0cbf7-090d-7910-b9ba-24a58dd4a886/session-ui-polish-20261007/`.

## Physical development installation

At the user's request, stable Xcode 27.0 built the normal device application from
the current sources. All **577** recorded source hashes match before signing and
after delivery. The existing Apple Development identity and installed development
profile were reused. The app and session widget retain their existing identifiers
and separate private Keychain groups; deep strict signature checks pass.

CoreDevice installed **1.0 (6)** on the connected iPhone 18 Pro Max (database
sequence **8968**) and launched it successfully. Read-back confirms version/build.
The app was updated without uninstalling it; saved records and credentials were
not inspected. Signed evidence remains outside Git:
`/private/tmp/maccompanion-session-polish-20261007-signed/report.json`.
The installation-time stable `bash scripts/validate.sh` rerun also passes with
exit zero: `/private/tmp/maccompanion-session-polish-install-validation-20261007.log`.

Physical feature acceptance and a new TestFlight upload remain separate next steps.
No commit, push, store submission or Mac-side installation occurred.

## Physical screenshot follow-up

The user's physical screenshots exposed remaining geometry problems in build 6.
This follow-up fixes the clipped first menu heading, excess menu padding, the
oversized blue close control, the Terminal button covering output, and light bands
around the Desktop canvas.

- The shared menu now owns a table constrained to a container's safe area, below
  the navigation bar. Keyboard-limited popovers keep the heading and title apart,
  size through the final real row, and scroll when space is insufficient. A quiet
  native Done button replaces the emphasized checkmark.
- Terminal reserves a 68-point controls dock outside its rows. Its UIKit keyboard
  layout guide owns avoidance while connected; SwiftUI still handles avoidance for
  the sign-in card. Avoiding the keyboard twice was also moving the button too high
  when Terminal colors changed inside a light app.
- Desktop's SwiftUI hosting safe area and status text follow the connected black
  canvas. Native controls use the corresponding dark palette. Sign-in restores the
  chosen app appearance, without changing the stored theme or session owner.
- Stable hosted Simulator verification passes **44 tests, zero failures** across
  adaptive layout, appearance, controls, Terminal and full-system captures:
  `/private/tmp/maccompanion-session-layout-fix-verified-20261007.xcresult`.
  Regression checks include the actual software keyboard, changing the connected
  Terminal palette, menu header visibility, preserved buffer/controller identity,
  and restoring the Desktop sign-in theme.
- Eight fresh synthetic system captures include the status area and keyboard:
  `/private/tmp/maccompanion-session-layout-fix-v3-20261007-captures/`.
  These stay outside Git. Large SwiftUI text captures supplement the native
  accessibility-layout tests; they do not replace physical acceptance.
- Required stable-Xcode `bash scripts/validate.sh` passes with exit zero:
  `/private/tmp/maccompanion-session-layout-fix-validation-20261007.log`.
- A fresh normal iOS device build passes. All **577** input hashes match before
  signing and after installation; existing app/widget identities and private
  Keychain groups are verified. CoreDevice installs and launches **1.0 (7)** on
  iPhone 18 Pro Max (sequence **8976**); installed version/build read-back agrees.
  Signed evidence: `/private/tmp/maccompanion-session-layout-fix-20261007-signed/report.json`.
  No uninstall or saved-record/credential inspection occurred. Physical session
  acceptance remains to be checked by the user.
- Local capture preview: `http://127.0.0.1:50635/layout-fixes/`.
