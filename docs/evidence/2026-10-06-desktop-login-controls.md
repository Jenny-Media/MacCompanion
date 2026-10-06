# Desktop readiness, saved logins and interaction feedback

## Scope

The direct iOS client continues to use built-in macOS Screen Sharing and Remote
Login. No Mac app/helper, target identity, server trust, entitlement or release
gate was introduced. Existing unrelated work in the checkout was preserved.

## Desktop rendering diagnosis and change

An isolated test using the pinned LibVNCClient decoder reproduced two defects:
a valid 1105 display-metadata reply could present a zero-filled framebuffer, and
a two-pixel strip could present only 2% of a framebuffer as the first desktop.
The native callback previously discarded rectangle coordinates and counted
metadata as pixel updates. The initial nonincremental request already existed.
The earlier phone counters did not record rectangle coverage, so they do not
prove the precise sequence of the user's photographed failure.

The owner now ignores metadata for pixel readiness, unions received rectangle
coverage, and waits for a complete baseline on allocation, resize, resume,
leaving input-only mode, or a changed host layout. Valid matching geometry
excludes display gaps; unknown geometry requires the whole framebuffer. Black
pixels remain valid. The previous presented image is retained while waiting,
and earlier allocation/lifecycle callbacks cannot establish readiness.

Coverage costs two bits per framebuffer pixel (at most 6 MiB within the existing
96 MiB pixel-buffer bound), and stops processing pixel coverage once ready.
Incomplete baselines receive at most two additional nonincremental requests,
one second apart, and end with a recoverable loading failure after eight seconds.
The viewer's nine-second resume fallback allows that window to finish. Normal
complete replies have no added waiting period. Diagnostics retain only fixed
counts/readiness/geometry, never pixel or input content.

## Other changes

- SSH setup displays connecting, adding, automatic key-only testing and saving
  phases. Rejected verification is classified as a key login failure and gives
  a bounded explanation. Prior password/key preference is preserved until the
  fresh login and durable association succeed; no password fallback or command
  replay was added.
- Desktop login covers the canvas, removing the exposed black strip. Fields
  remain in place but are inactive during connection. The short transition
  respects Reduce Motion. Password visibility uses its explicit button reference.
- Edit Mac offers Desktop Login and Terminal Password Login editors. Existing
  device-local per-Mac/service Keychain items change only on Save. Failed reads
  block editing, failed writes preserve drafts, Cancel preserves saved data, and
  dismissal/background clears drafts. Editing does not connect, change a Mac's
  account password, or change selected SSH keys/trust.
- Session Controls has subtle press compression, short glass-menu animation,
  light opening/release feedback and a tick when moving onto a new choice.
  Cancellation is neutral; disabled actions cannot run. Feedback indicates local
  selection rather than remote completion. Settings > Session > Controls Haptics
  is a device-local opt-out, and Reduce Motion suppresses scale/translation.

## Verification

Stable Xcode 27.0 (27A266a), dedicated Mac Companion Pro QA Simulator, isolated
`dev.maccompanion.proqa.ios` app/Keychain:

- 105 Simulator tests passed, zero failures/skips. Actual decoder/socket-owner
  regressions cover metadata, partial strips, valid black frames, overlap/gaps,
  resize, retained-socket resume and two bounded full-refresh retries/deadline.
- Synthetic SSH integration covers fresh verification, rejection, prior login
  preservation and no fallback/replay; OpenSSH export interoperability and
  sandboxed authorized_keys preservation/idempotence/permissions checks passed.
- Saved-login tests cover explicit Save, Cancel, read/write failure, per-Mac and
  per-service isolation, bounds and draft clearing.
- Controls tests cover selection without premature dispatch, neutral cancellation,
  haptics opt-out, Reduce Motion and portrait/landscape/keyboard bounds.
- Light/dark login and saved-login screens, accessibility-size saved-login screens,
  and the final floating-controls screenshot were inspected. Synthetic screenshots
  and result bundles remain outside Git under the Simulator and /private/tmp.

Final required repository validation is recorded separately below. An initial
run hit an existing fixed signing-tool two-second execution timeout while
Simulator QA was active; the subsequent serialized run passed that check.

No new physical-device installation or TestFlight upload occurred in this change.
The user's partial-desktop episode and haptic feel still need a physical smoke
test on the updated build. Simulator success is not physical acceptance or a
production release admission.

Required validation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/validate.sh` completed with exit 0 after Simulator QA finished.
`git diff --check` passed. The validation log is outside Git at
`/private/tmp/maccompanion-usability-validation-final-20261006.log`.
