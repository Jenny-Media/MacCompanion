# Persistent Terminal toolbar — 2026-10-07

## Approved design

The connected Terminal keeps one modifier bar visible with a keyboard toggle
at its leading edge and the existing shared controls button at its trailing edge.
The middle keys scroll horizontally on narrow screens rather than shrinking
below 44 points. The shared button retains tap, press-and-slide, feedback and
above-button menu placement. Terminal keyboard Show/Hide actions are removed
from the quick panel, category menu and Fn menu; the toolbar owns that toggle.

The number row appears above the modifier bar while the software keyboard is
visible, together with any existing admitted Pro custom-key row. With a closed
or hardware-only keyboard, only the modifier bar remains. Existing one-shot and
locked modifiers, function keys, snippets and protected preferences are retained.

## Implementation

`TerminalKeyboardBar` replaces the keyboard-owned input accessory with a
persistent native view constrained to `keyboardLayoutGuide`. The old 68-point
button dock is removed. The toolbar is 60 points with the keyboard closed and
108 points with the number row visible, or 156 with the custom-key row. The
previous default keyboard-open layout reserved 100 + 68 points, so the default
new layout returns 60 points to output, before whole-row rounding.

A weak optional toolbar anchor lets `CompanionVNCControls` use the bar's trailing
slot while retaining the same button and gestures. Desktop and Trackpad keep
their existing placement. The toolbar lays out before the overlay positions its
button. Window-relative keyboard visibility covers hosting-controller resizing;
comparing only with the child's bottom had hidden the number row in a SwiftUI
host. No custom keyboard frame notification observer or input accessory is added.

The native scroll-edge treatment, protected initial top inset, whole-row PTY
resize, session/buffer ownership, foreground recovery and tabletop viewport rules
remain in place. Disconnected recovery hides both the toolbar and controls.

## Verification

- Stable Xcode 27.0 (27A266a) build succeeds.
- Required `bash scripts/validate.sh` succeeds on stable Xcode.
- 13 focused hosted Simulator checks pass in the final run. They cover actual
  keyboard toggling, restored grid and buffer, fixed narrow end controls,
  scrolling keys and reachable Fn, palettes, recovery, tabletop regions, native
  status-area scrollback, modifiers, settings and shared feedback/slide behavior.
- Eight full-system synthetic Simulator captures show keyboard open/closed,
  the quick panel and Session menu in both palettes. Visual inspection confirms
  the number row, toolbar anchor, readable prompt and above-button menu placement.
- An initial palette run had a keyboard-frame mismatch; the final full focused
  run passes after the hosted visibility and anchor layout corrections. Earlier
  captures missing the number row were replaced and are not acceptance evidence.

Evidence stays outside Git:

- `/private/tmp/maccompanion-terminal-bar-20261007-validation.log`
- `/private/tmp/maccompanion-terminal-bar-20261007-final.xcresult`
- `/private/tmp/maccompanion-terminal-bar-20261007-captures/`

At the original toolbar verification this was not installed, committed, pushed
or published. The installation below includes the toolbar and number-row choice.
Simulator verification does not establish real-device behavior.

## Follow-up: optional number row

Terminal's shared controls menu now includes **Keyboard & Input → Show Number
Row**, with a native checkmark and selected accessibility state. The default is
On. Selecting the item immediately resizes the toolbar and the live PTY grid
without changing the session or keyboard focus. A global, non-sensitive
UserDefaults choice restores it in later sessions; the protected per-Mac custom
keys and snippets retain their existing format and Pro policy. The number-row
choice is free and independent of custom keys.

With the software keyboard open, turning numbers Off reduces the standard bar
from 108 to 60 points. An admitted custom row still has its own 48 points. With
the software keyboard closed, the modifier bar stays 60 points regardless of
this preference. The keyboard button, modifier keys and shared menu button
remain available.

Follow-up verification:

- Required stable-Xcode `bash scripts/validate.sh` succeeds.
- 11 focused hosted checks pass, including real menu selection, On/Off state,
  persistence in a new controller, keyboard focus and retained buffer, restored
  PTY space, native status scrolling, palettes and existing modifier behavior.
- Four full-system synthetic captures show numbers On/Off and the checked/
  unchecked menu. Visual inspection confirms the persistent controls and the
  additional output space.
- The first shared-Simulator run was interrupted by another app, invalidating
  some captures. A dedicated iPhone 18 Pro Max Simulator replaced them. Its first
  launch needed boot completion. An existing keyboard test now waits for popover
  dismissal completion before hiding the keyboard; the final focused run passes.

Follow-up evidence outside Git:

- `/private/tmp/maccompanion-terminal-number-row-20261007-validation.log`
- `/private/tmp/maccompanion-terminal-number-row-20261007-verified.xcresult`
- `/private/tmp/maccompanion-terminal-number-row-20261007-final-captures/`

Normal development **1.0 (14)** is built, signed, installed and launched on iPhone
18 Pro Max. All 577 source inputs, the signed binary and existing app/widget
identities and private Keychain groups are verified. CoreDevice confirms build
14 and installation sequence 9120. Installation evidence and the signed report
are outside Git:

- `/private/tmp/maccompanion-terminal-toolbar-20261007-device/build-report.json`
- `/private/tmp/maccompanion-terminal-toolbar-20261007-signed/report.json`
- `/private/tmp/maccompanion-terminal-toolbar-20261007-install.json`
- `/private/tmp/maccompanion-terminal-toolbar-20261007-launch.json`
- `/private/tmp/maccompanion-terminal-toolbar-20261007-app-after.json`

Physical acceptance is pending; no commit, push or TestFlight publication occurred.
