# Shared Desktop and Trackpad & Keyboard sign-in

Trackpad & Keyboard uses Desktop's centered credential card, progress and inline
recovery presentation. Its header now identifies the mode with its name and icon.
Both modes share folded-screen sign-in placement and move the card above a tall
keyboard. The connected input-only surface retains its existing full input area;
the separate tabletop video/input regions still belong to Desktop.

This is presentation only. Screen Sharing authentication, saved Desktop login
ownership and input-only network behavior are unchanged.

## Verification

- Required stable-Xcode `bash scripts/validate.sh` passes.
- All 30 distinct focused hosted checks pass across adaptive layout, appearance,
  recovery, client additions and synthetic captures. Portrait/progress and folded
  login checks run in both modes. They verify keyboard avoidance, draft retention,
  mode identity and the existing session owner.
- One older fullscreen test initially compared connected geometry with geometry
  measured before the connected chrome had settled. Its setup now settles the
  connected layout before measuring; the test passes on rerun. Production
  fullscreen geometry is unchanged by this follow-up.
- 24 synthetic captures cover Desktop and Trackpad & Keyboard sign-in, progress,
  errors and menus in light, dark and accessibility text sizes. Selected login,
  progress, error and large-text captures were visually inspected. Images remain
  outside Git, with synthetic credentials only.
- The normal device app and extension are signed as **1.0 (12)**. All 577 inputs
  and the signed binary match the current source. The update is installed and
  launched on iPhone 18 Pro Max, with version/build read-back and installation
  sequence **9088**. Physical acceptance remains pending.

Local evidence:

- `/private/tmp/maccompanion-input-login-20261007-tests.xcresult`
- `/private/tmp/maccompanion-input-login-20261007-fullscreen-recheck.xcresult`
- `/private/tmp/maccompanion-input-login-20261007-captures/`
- `/private/tmp/maccompanion-input-login-20261007-validation.log`
- `/private/tmp/maccompanion-input-login-20261007-device/build-report.json`
- `/private/tmp/maccompanion-input-login-20261007-signed/report.json`
- `/private/tmp/maccompanion-input-login-apps-20261007.json`

No commit, push or TestFlight publication is requested for this follow-up.
