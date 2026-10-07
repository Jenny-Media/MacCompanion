# Concise login and headerless Terminal

## Changes

- Desktop retains its saved-login automatic entry. Terminal now also loads the
  saved password/selected key and starts one eligible attempt on entry. An
  incomplete login shows account fields and one Connect action.
- Active connection attempts show progress and Cancel. Setup, password-manager
  information and network/privacy explanations remain in Details/Options.
  Fields remain mounted and drafts survive validation failure.
- Terminal has no connected title/navigation bar. A bottom-right floating
  control uses the same tap, press-and-slide, cancellation, haptic preference and
  reduced-motion behavior as Desktop. Categories are Keyboard & Input,
  Appearance and Session; quick actions are keyboard toggle, Paste, Ctrl-C and
  Done. Fn keeps extra keys and snippets available in the keyboard accessory.
- The floating button moves above the software keyboard/accessory. The emulator
  stays mounted through recovery and layout changes; the closed keyboard leaves
  the full available terminal height. Controls/input are disabled when disconnected.
- Shared popup symbols and captions use compatible Dynamic Type traits.

SSH identity checks, saved credentials, server-trust records, endpoint fallback
and authentication implementations are unchanged. A first unknown SSH identity
still requires verification before credentials are sent. Failed attempts are not
automatically retried, and trust-sheet dismissal does not create another session.

## Verification

Stable Xcode 27.0 normal Simulator development build passes with matched input
hashes. The final hosted direct-client suite passes: 129 tests, one intentional
interactive-Duo capture skip, zero failures. This includes saved-password entry
without Connect, trust-before-authentication, exactly one authentication attempt,
persistent rejected-login recovery, real PTY delivery of floating Ctrl-C,
press-and-slide commit/cancellation, buffer preservation and adaptive layouts.
OpenSSH encrypted export and sandboxed key-install preservation checks pass.

Required stable `bash scripts/validate.sh` completed with exit zero during this
work. Final UI source also builds and passes the hosted suite after the font/
caption corrections. Final `git diff --check` passes.

Light/dark/large-text login, progress and floating controls were captured and
visually inspected. A focused capture also passes and supplies a full Simulator
screenshot including the actual system keyboard, number/modifier accessory and
floating button above them. App-window captures alone omit that system window.
Screenshots and the local HTML gallery remain outside Git, in the task's
`2026-10-06-session-login-review` visualization folder.

The first suite had one obsolete expectation that fields stayed visible during
progress; it was replaced with hidden-progress/draft-restoration coverage. That
failed runner stalled during result finalization and was terminated; its log is
kept separately in the temporary QA folder. The completed final suite has no
failures. A subsequent focused capture build initially lacked the temporary key
resources removed by the successful full-run cleanup; fresh synthetic resources
were generated for the passing capture and cleaned up again.

No iPhone installation, commit or TestFlight upload was performed for these UI
changes. Physical haptics, real-device gesture acceptance and exact distribution
build acceptance remain unverified.

The closed-lid investigation is paused and preserved separately in the
[MacTools capture handoff](2026-10-06-mactools-closed-lid-capture.md).
