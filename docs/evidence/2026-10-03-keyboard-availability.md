# Keyboard availability and development installation — 2026-10-03

## Change

Opening the iOS keyboard is local presentation throughout an approved Control
session, including Desktop, a missing focused field, and view replacement.
It does not request Text authority or change the Mac focus. The optional local
composer retains its separate verified editable, nonsecure focus binding.

Remote input remains gated by current Control/Keyboard authority and native
presentation admission. View replacement pauses recognizers and delivery without
resigning the local keyboard responder. Local composition and modifier selection
clear at the pause; paused commits are discarded and never replayed on the new
surface. Pickers restore an already-open keyboard when dismissed. Actual
background entry, Stop, and terminal retirement still dismiss local input.

Each unmodified commit checks the current acknowledged Text authority and latest
admitted focus. When Unicode Text is unavailable, supported ASCII commits of at
most 32 characters use the existing balanced physical key path. Mac keyboard
layout and secure-input restrictions still apply. Unsupported commits are
omitted as a whole with a content-free local notice. No wire payload, grants,
secure Text refusal, pairing, approval, or authentication semantics changed.

## Verification

- Required `bash scripts/validate.sh` passes with stable Xcode 27.0 (27A266a)
  and 121 indexed fixtures. Private log:
  `/private/tmp/maccompanion-keyboard-final-v3-validation-20261003.log`.
- Indexed software keyboard vectors cover Unicode, modifiers, physical-only
  ASCII, shifted punctuation, whole-commit omission, and the fallback bound.
- Seven UIKit/coordinator tests pass, including real UITextField responder
  retention during pause, disabled recognizers, discarded paused commits,
  modifier clearing, marked-text discard before resumption, no replay, and
  dismissal on retirement.
  Private results: `/private/tmp/maccompanion-keyboard-uikit-tests-20261003/Tests-v3.xcresult`.
- Normal paired Simulator journey passes five native presentations: two Control
  starts, two display replacements, and a selected Window. Keyboard restoration
  after display/Window pickers, ordinary keyboard input, modifiers, pointer,
  shortcuts, Stop/restart, TLS/pairing, and cleanup pass. Simulator state and
  private test keys are restored. The Mac approval is substituted by a disposable
  test authority; final input is synthetic. No physical input acceptance is
  claimed. An earlier v2 run stopped at an undelivered Shared Display menu tap
  before switching; its cleanup passed. Its cause is unconfirmed. The final
  journey passes on v3 without an automation retry or approval substitution
  change. The normal native menu now omits the unsupported composer action;
  that action is offered only for an eligible verified Focused Region. Private report:
  `/private/tmp/maccompanion-keyboard-switch-v3-qa-20261003/report.json`.
- Normal source/native input SHA-256:
  `df38cd48ab2d5d40813da4135d5162e9e03337a0d02628fed507a07018d94bb2`.

## Installed development updates

The signed normal Mac app is installed at
`/Users/yihong/Applications/Mac Companion.app`. Its existing Agent service and
Keychain entitlements are reused; all 119 files of the verified Sunshine package
are unchanged. The prior app is retained as a private rollback copy. Private
installation receipt: `/private/tmp/maccompanion-keyboard-mac-installed-20261003.json`.

The signed normal iOS app is installed on the paired iPhone 18 Pro Max using the
existing provisioning profile, application identity and Keychain entitlements.
No uninstall or data reset was performed. Private receipt:
`/private/tmp/maccompanion-keyboard-iphone18-install-v3-20261003.json`.
The final update's automatic launch is blocked because the phone is locked;
unlock and open Mac Companion for physical testing. Private launch diagnostic:
`/private/tmp/maccompanion-keyboard-iphone18-launch-v3-20261003.log`.
Signed iPhone executable SHA-256:
`7a407368d1dcbc99fe9a53f210339e183278079e1fb3ea9a6460056c10e3bfc3`.

Physical keyboard behavior, input-method/layout compatibility, and secure-field
acceptance remain user-device checks. View switching still uses the existing
native replacement/reconnection path; this change does not implement connection
reuse or establish production release readiness.
