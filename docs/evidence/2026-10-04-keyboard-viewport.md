# Keyboard viewport and dismissal

## Behavior

The docked iOS keyboard reduces the available desktop viewport and raises the
keyboard strip and floating controls. A fitted desktop fits the smaller area;
a zoomed desktop preserves its relative zoom and normalized center. Closing the
keyboard restores the prior viewport when its display crop is still valid.
Selecting another display or changing framebuffer geometry invalidates that
snapshot, so dismissal cannot bring back an obsolete crop. Floating keyboards
do not shrink the entire viewport. Layout uses the system keyboard animation
duration and curve instead of a fixed delay.

The keyboard button uses the system keyboard symbol when closed and the
keyboard-with-down-chevron symbol while the remote input owns focus. Its
accessible label changes between Show Keyboard and Hide Keyboard, including
when focus changes outside the button. This is a local viewport adjustment;
it does not reconnect RFB, resize the Mac desktop, or change authentication/input
semantics. Focused Mac text fields are not identified by this change.

The direct Screen Sharing specification and the existing indexed fixture
describe these policies. No second fixture corpus or Mac helper is added.

## Verification

Toolchain: `/Applications/Xcode.app`, Xcode 27.0.

- **39 hosted tests passed, 0 failed, 0 skipped**:
  `/private/tmp/maccompanion-keyboard-viewport-verified-tests-20261004.xcresult`.
- Actual UIKit viewer tests verify fitted and zoomed keyboard reflow, controls
  above the keyboard, changing keyboard height, zoom/center restoration,
  floating-keyboard handling and no connection start during reflow.
- A display change while the keyboard is open retains the new display after
  dismissal. An actual first-responder test verifies show/hide labels and both
  system symbols. Tests use only synthetic framebuffer and input data.
- The normal iPhone app builds, and all 480 source input hashes match the signed
  app. Its existing device profile, Keychain group, ActivityKit extension and
  deep signatures verify. Signed binary SHA256:
  `7864d74bad5cba2378d7bdf77ef546952abacc6740c6b90bac64fb3ad2088fe8`.
- Required `bash scripts/validate.sh` exits 0 on the stable Xcode lane:
  `/private/tmp/maccompanion-keyboard-viewport-validation-20261004.log`.

## Installation and acceptance

Signed update:
`/private/tmp/maccompanion-keyboard-viewport-signed-ios-20261004/Mac Companion.app`.
Installation succeeds on iPhone 18 Pro Max (database sequence 8196), preserving
app data. `devicectl` launch also succeeds. Physical acceptance remains pending
and should cover opening/closing the keyboard while
fitted and zoomed, with the desktop visible above it and the dismiss symbol shown.
No real credential or typed content is captured. No commit or publication is made.
