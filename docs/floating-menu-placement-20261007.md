# Floating control menu placement — 2026-10-07

## Cause and change

The category popover left arrow direction unrestricted. UIKit could place it
beside the lower-right controls button, as shown in the physical screenshot.
Apple documents the default as any direction in
[permittedArrowDirections](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/permittedarrowdirections).

`CompanionVNCMenu` now shares one native navigation/popover setup for category
menus and display selection. Its arrow points down toward the button, placing
the content above it. UIKit continues to own geometry, scroll fitting and
keyboard avoidance. Pushed pages keep their navigation controller and anchor.
No connection, input, authentication or wire behavior changed.

## Route audit

| Entry from floating controls | Presentation |
| --- | --- |
| Desktop and Trackpad quick actions and categories | Existing shared panel above button |
| Desktop/Trackpad View & Display, Keyboard & Input, Session | Shared popover above button |
| Desktop Extra Keys, Function Keys, Choose Display | Shared popover; nested pages keep anchor |
| Terminal quick actions and categories | Same shared panel above button |
| Terminal Keyboard & Input, Appearance, Session, SSH Keys | Shared popover; nested SSH Keys keeps anchor |
| Input preferences, app/Mac settings, key management/setup, keyboard customization | System editor sheets with their own dismissal controls |
| Connection details and Desktop gesture help | System centered alerts |
| Quick toggles, paste, shortcuts and saved text | Direct actions through the existing session owner |

Terminal's keyboard Fn menu uses a system menu anchored to Fn. It is separate
from the floating controls routes above.

## Verification

- Stable Xcode 27.0 required `bash scripts/validate.sh` passed.
- Eight distinct focused hosted checks passed across the recorded runs: menu
  geometry/navigation, shared slide actions, haptics, folded/short layout and
  synthetic/full-system capture checks.
- Thirty-four synthetic panel/popover states verify actual arrow direction,
  bounds above the button, status-safe placement and reachability of the final
  action. These cover all button-anchored routes with keyboard open and closed.
- Eight full-system Simulator captures include the system keyboard and visible
  Desktop/Terminal menus. Light, dark and large-text Terminal host states are
  included. When space is constrained, longer menus scroll.
- Initial capture/navigation failures were harness transition timing: waiting
  for UIKit presentation, dismissal and push completion resolved them.
- App-window rendering returned black for some keyboard states. Those images
  are not visual acceptance evidence; full-system captures verify those states.

## Local evidence

- `/private/tmp/maccompanion-above-controls-20261007-validation.log`
- `/private/tmp/maccompanion-above-controls-20261007-final.xcresult` — geometry
  sweep passed; the navigation timing check failed before its repair.
- `/private/tmp/maccompanion-above-controls-20261007-navigation.xcresult` — final
  navigation, slide and haptic checks passed.
- `/private/tmp/maccompanion-above-controls-20261007-system.xcresult` — full-system
  capture check passed.
- `/private/tmp/maccompanion-above-controls-20261007-captures/`
- `/private/tmp/maccompanion-above-controls-20261007-system-captures/`

Synthetic screenshots remain outside Git. This follow-up is included in normal
development **1.0 (14)**, installed and launched on iPhone 18 Pro Max. CoreDevice
confirms build 14 and installation sequence 9120; see the installation evidence
in [the Terminal toolbar follow-up](terminal-persistent-toolbar-20261007.md#follow-up-optional-number-row).
It has not been committed, pushed or published. Physical acceptance is pending.
