# Terminal scrolling behind the status bar

## Accepted behavior

The user confirmed that brief app switching preserves Terminal, then clarified
the desired top-edge behavior: scrollback should move behind the system status
bar, while sign-in and initial useful output stay clear of it.

The earlier safe-area-pinned terminal could never scroll into the status area.
Matching its background color did not change that clipping boundary.

## Implementation

- Only the connected terminal canvas extends to the top screen edge. Sign-in,
  connection progress, trust and recovery UI retain normal safe-area layout.
- A leading scroll inset uses the physical window safe area plus eight points.
  Initial output rests below the icons, including when SwiftUI removes the native
  child's top safe area. SwiftTerm's zero-offset short-buffer follow position is
  corrected to include this inset; finger tracking and deceleration remain under
  UIKit's control.
- The PTY and emulator grid use the unobscured viewport, in whole rows. Live
  output and alternate-screen programs keep their interactive top row below the
  status icons, and their final row above the floating controls and keyboard.
  Scrollback can occupy the extra space above that grid.
- A noninteractive, palette-matched gradient fades history behind the icons. It
  does not introduce another terminal, intercept touches or reset the emulator.
- Existing SSH lifecycle, app-unlock gates, modifier behavior and menu ownership
  are retained. No background assertion, network protocol, authentication or
  security behavior changes in this follow-up.

## Verification

- Stable Xcode 27.0 (27A266a): 23 focused hosted tests pass. The new regression
  verifies the real SwiftUI/native canvas reaches the screen edge, initial
  output and caret are protected, history crosses behind system icons, first
  history remains reachable, keyboard transitions preserve a usable PTY grid,
  and alternate-screen entry/exit retains the normal buffer. Existing theme,
  menu, app-switch and in-process SSH tests also pass.
- Eight before and eight after synthetic full-system Simulator screenshots:
  sign-in, initial output, scrollback and keyboard-open scrollback in both
  palettes. The after images visibly show faded history behind the system
  clock and icons, with protected initial output and sign-in fields.
- Screenshots and test artifacts remain outside Git. No real machine login,
  password, SSH key material or terminal output is captured.
- `bash scripts/validate.sh` passes with stable Xcode. The normal iPhoneOS app
  and extension compile; all 577 source/dependency inputs and existing private
  app/widget signing identities verify. `git diff --check` also passes.

Local evidence:

- `/private/tmp/maccompanion-terminal-immersive-before-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-immersive-first-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-immersive-regression-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-immersive-before-20261007-captures/`
- `/private/tmp/maccompanion-terminal-immersive-after-20261007-captures/`
- `/private/tmp/maccompanion-terminal-immersive-validation-20261007.log`
- `/private/tmp/maccompanion-terminal-immersive-20261007-device/build-report.json`
- `/private/tmp/maccompanion-terminal-immersive-20261007-signed/report.json`

The single-page before/after comparison, with both palettes, is served locally
at `http://127.0.0.1:50636/`. It uses synthetic full-system images outside Git.

## Physical delivery

Local development **1.0 (9)** is installed and launched on iPhone 18 Pro Max.
CoreDevice reads back build 9 and installation sequence **9064** for the existing
`media.jenny.maccompanion.ios` bundle. The app and private Keychain identities
are preserved. The user confirmed app switching for build 8 and requested
replacing build 9's custom fade with the native effect described below. Physical
acceptance of the final native treatment is recorded in that follow-up.

No commit, push or TestFlight publication occurred at this build's delivery.
The user subsequently requested a local commit after accepting the native effect.

## Native visual treatment follow-up

After comparing the physical device appearance with another app, the user
requested using iOS's native scroll-edge effect. The custom gradient above is
superseded by
[`terminal-native-scroll-edge-20261007.md`](terminal-native-scroll-edge-20261007.md).
The initial inset, usable terminal grid and keyboard geometry are retained.
