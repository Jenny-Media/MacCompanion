# Approved connection sheets

## Implemented design

The approved v2 mockups are implemented for Desktop and Terminal entry:

- A bottom-aligned, rounded connection sheet sits over a blurred passive view of
  saved Mac names. Reduce Transparency uses an opaque grouped background.
- A shared icon tile, Mac name and service subtitle identify the destination.
  The close control cancels entry; connection progress has one Cancel action.
- Grouped account/password fields, an integrated visibility button, quiet Save
  login and one full-width Connect action replace the verbose main entry view.
  Terminal offers a compact Password/SSH Key selector and the existing key chooser.
- Saved credentials continue to make one automatic connection attempt. Progress
  uses the real session phase and retains the selected Mac identity.
- Login errors appear inline above retained fields. The main message is short;
  Connection Details preserves setup/privacy guidance, original explanations and
  fixed diagnostics. Confirmed key rejection offers Set Up Key and Use Password,
  without assuming that a missing public key is the only possible cause.
- App Light/Dark preferences remain respected. The sheet scrolls when necessary,
  retains the adaptive landscape credential columns, and stacks Terminal's auth
  selector at accessibility text sizes. Symbol sizes remain within touch targets.
- Connected Terminal remains headerless, with the existing floating tap and
  press-and-slide controls. Its emulator stays mounted through recovery/layout.

These changes are presentation-only. Authentication, SSH trust-before-login,
Keychain scoping, endpoint fallback, session ownership and decoder behavior are
preserved. No wire/security fixture changes were introduced by this UI work.

## Visual review

Native Simulator captures cover login, actual progress and synthetic rejection
in both themes, plus accessibility text sizes and connected Terminal controls.
The first visual pass caught a UIViewRepresentable password field accepting an
oversized proposed height. Its sizing now uses intrinsic text height; a hosted
layout assertion guards against the stretched field. A subsequent large-text
review caught a split Password selector; the auth row now stacks at accessibility
sizes and fixed-size symbols preserve their touch targets.

Approved mockup and implemented native screenshots are compared in the local
`2026-10-06-session-login-review/implemented-v2/` visualization folder, outside
Git. All captured names/accounts/content are synthetic. App-window captures omit
separate system status/software-keyboard windows; they are not physical evidence.

## Verification

Stable Xcode 27.0 normal Simulator build passes, with all 577 input hashes matching
current source. The hosted direct-client suite passes: 129 tests, one intentional
interactive-Duo capture skip, zero failures. OpenSSH encrypted export and the
sandboxed key-install preservation/duplicate/link/permissions checks also pass.

After the final Desktop details-retention adjustment, 10 focused recovery,
Terminal layout and native screenshot tests pass with zero failures. This includes
original error guidance and port/stage diagnostics surviving the inline notice,
then clearing when the login is edited. Final captures show the corrected field
height and accessibility selector. Required stable `bash scripts/validate.sh`
passes after the final native source changes. `git diff --check` passes.

The local comparison page loads all Desktop/Terminal and Light/Dark images,
responds with HTTP 200, and passes 1280/390-pixel browser checks without missing
images, page errors or horizontal overflow. The in-app preview request is queued;
the URL is usable at `http://127.0.0.1:4191/implemented-v2/`.

No iPhone installation, commit or TestFlight upload is part of this UI update.
Physical acceptance remains separate. The MacTools closed-lid capture investigation
is still paused; see [the preserved handoff](2026-10-06-mactools-closed-lid-capture.md).
