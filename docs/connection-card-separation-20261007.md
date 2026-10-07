# Centered connection card separation — 2026-10-07

## Scope

Desktop, Trackpad & Keyboard and Terminal retain the approved centered login,
progress and recovery layout. Shared presentation now uses an elevated system
background, semantic field colors, a subtle adaptive border, soft shadow and
neutral theme-aware backdrop dimming. Native blue Cancel controls clearly
indicate that cancellation is available.

The presentation lives in `DirectConnectionPresentation.swift`, with UIKit
integration in `CompanionVNCViewer.m` and SwiftUI integration in
`DirectTerminalView.swift`. No connection, authentication, trust or wire behavior
changed. Shadow, radius and dimming values are product design choices.

## Verification

- Required `bash scripts/validate.sh` passed under stable Xcode 27.0 (27A266a).
- Eight focused hosted checks passed, covering adaptive placement, cancellation,
  appearance ownership, desktop viewport geometry and shared captures.
- Thirty-six synthetic app-window captures cover each mode's login, progress and
  recovery in light, dark, large text and increased contrast. These are not
  physical-device or full-system captures.
- The existing opaque Reduce Transparency fallback remains in code. Simulator
  attempts did not expose the enabled system setting to UIKit, and the capture
  configuration assertion correctly failed. The temporary setting was restored;
  rendering with this option remains a physical-device check.
- Normal device app and extension are development-signed as **1.0 (13)**. All
  577 source inputs and the signed binary match; existing app/widget and private
  Keychain identities are retained. The requested installation failed to acquire
  CoreDevice connectivity and power assertions while iPhone 18 Pro Max was
  unavailable. The user's authorized retry installed and launched the update;
  CoreDevice confirms **1.0 (13)** and installation sequence **9104**. Physical
  acceptance remains pending.

## Local evidence

- Validation log: `/private/tmp/maccompanion-card-separation-20261007-validation.log`
- Focused result: `/private/tmp/maccompanion-card-separation-20261007-final.xcresult`
- Captures: `/private/tmp/maccompanion-card-separation-20261007-captures/`
- Summary boards: `shared-progress-comparison.jpg` and
  `login-error-accessibility-review.jpg` in that capture directory.
- Device build: `/private/tmp/maccompanion-card-separation-20261007-device/build-report.json`
- Signed update: `/private/tmp/maccompanion-card-separation-20261007-signed/report.json`
- Installation attempt: `/private/tmp/maccompanion-card-separation-install-20261007.log`
- Successful retry: `/private/tmp/maccompanion-card-separation-install-retry-20261007.json`
- Launch: `/private/tmp/maccompanion-card-separation-launch-20261007.json`
- Installed version read-back: `/private/tmp/maccompanion-card-separation-apps-20261007.json`

Captures remain outside Git. This follow-up has not been committed, pushed or
published to TestFlight.
