# Remote Desktop with native status-area scrolling

## Behavior

The connected desktop canvas reaches the top screen edge, matching Terminal.
A zoomed desktop can pan behind the status icons. UIKit supplies its automatic
top scroll-edge effect; no custom blur, gradient, placeholder bar or image
sampling is added. Sign-in and input-only mode retain normal safe-area layout.

Fit Display uses the unobscured canvas below the physical status safe area plus
eight points. The entire selected display remains reachable. Centering, zoom
restoration, keyboard resizing and cursor following use the same visible region
and inset-aware offset bounds. Pointer coordinates still come from the actual
image/crop conversion. These are local presentation changes; the direct VNC
connection and Mac's built-in Screen Sharing service are unchanged.

## Verification

- Stable Xcode 27.0: the normal Simulator and device applications build.
- 45 distinct focused hosted checks pass across appearance, display viewport,
  adaptive layout, session controls and synthetic captures. The new hosted check
  verifies the real SwiftUI/native canvas reaches the top edge, Fit is unobscured,
  zoom/center survive controls and software-keyboard changes, the session owner
  is retained, and input-only/sign-in leave immersive presentation.
- Eight synthetic full-system captures were inspected: sign-in, bright/dark Fit,
  bright/dark panning, keyboard, menu and controls-hidden mode. The native blur is
  visible behind system icons; Fit and sign-in stay clear of them. Captures remain
  outside Git, with no real Mac screen, login or input content.
- Required stable-Xcode `bash scripts/validate.sh` passes in full. Two earlier
  attempts hit startup deadlines in unchanged helper checks: the legacy managed
  preparation test, then the fixed-tool overflow test. Both passed when rerun
  alone, and the final complete run passed without changing either check.
- The normal app and extension are development-signed as **1.0 (11)**. All 577
  build inputs and the signed binary match the current source. The first device
  installation attempt could not acquire CoreDevice's required connectivity and
  power assertions. The user's later authorized retry succeeded: the normal app
  is installed and launched on iPhone 18 Pro Max. CoreDevice confirms version
  1.0, build 11 and installation sequence **9080**. The user confirmed the desktop
  result looks good and requested a local commit.

Local evidence:

- `/private/tmp/maccompanion-desktop-immersive-regression-20261007.xcresult`
- `/private/tmp/maccompanion-desktop-immersive-capture-tests-20261007.xcresult`
- `/private/tmp/maccompanion-desktop-immersive-system-capture-20261007.xcresult`
- `/private/tmp/maccompanion-desktop-immersive-captures-20261007/`
- `/private/tmp/maccompanion-desktop-immersive-20261007-legacy-recheck.log`
- `/private/tmp/maccompanion-desktop-immersive-20261007-fixed-tools-recheck.log`
- `/private/tmp/maccompanion-desktop-immersive-20261007-validation-complete.log`
- `/private/tmp/maccompanion-desktop-immersive-20261007-device/build-report.json`
- `/private/tmp/maccompanion-desktop-immersive-20261007-signed/report.json`
- `/private/tmp/maccompanion-desktop-immersive-install-20261007.json`
- `/private/tmp/maccompanion-desktop-immersive-install-now-20261007.json`
- `/private/tmp/maccompanion-desktop-immersive-launch-now-20261007.json`
- `/private/tmp/maccompanion-desktop-immersive-apps-now-20261007.json`

Physical installation and the user's visual acceptance are recorded separately
from Simulator verification. The user requested a local commit; this follow-up
has not been pushed or published to TestFlight.
