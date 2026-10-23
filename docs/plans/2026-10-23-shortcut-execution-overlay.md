# Shortcut execution ownership and progress

Use one connection-owned shortcut reservation for both immediate and timed
shortcuts in Terminal, Screen Sharing, and Trackpad & Keyboard. Reject another
shortcut and ordinary remote input while reserved; keep incoming output and
terminal protocol replies flowing. Preserve batching, transport order, bounded
queue accounting, and prompt cancellation of unsent suffixes. Old callbacks
must never finish a newer run.

Replace the banner above the keyboard with a shared execution surface covering
the existing keyboard rows and floating menu slot. Block their interaction and
accessibility immediately. Show the native glass surround, solid progress
content, current step/countdown, and Cancel after 180 ms; quick shortcuts must
not flash a progress surface or delay sending. Restore rows, scroll positions,
keyboard focus, and menu interaction on every completion/retirement path.
Allow extra row height only when needed for readable Dynamic Type content.

Validate shortcut definitions independently of presentation changes. Disable
row expansion, keypad, keyboard toggle, saved actions, and remote gestures while
executing; Cancel remains the only execution action. No wire/auth changes or
new persistence format are required.

Add regressions for no-wait admission ownership, rejected competing runs,
blocked-write Cancel/late completion, retained queue budget, definition versus
layout validity, progress hit coverage/restoration and delayed presentation in
both remote modes. Exercise live loopback SSH input, output/protocol replies,
Cancel, keyboard-visible/hidden and expanded rows in Simulator. Capture actual
screenshots, run the stable Xcode managed QA and scripts/validate.sh, then build,
sign, install and launch development build 155 on the iPhone 18 Pro Max.
Keep evidence outside Git. No PR, push, merge or TestFlight upload is included.

The final accessibility pass requires an explicit minimum-height constraint;
relax the covered keys' bottom constraint so their fixed heights cannot
compress progress. Bound that temporary height by the space above the keyboard,
allow large status text to scroll, and keep Cancel visible. Cover restoration
and a constrained viewport in the native layout regression.

## Glass and temporary keyboard polish

Keep the real row keycaps recognizable below one native UIKit glass backdrop,
with a solid central status strip. Touch and accessibility blocking, including
the floating button, remains immediate; Cancel is the sole execution control.
Respect Reduce Transparency, including changes while progress is visible.

After 500 ms of sustained execution, temporarily dismiss a visible docked
software keyboard. Keep transport ownership, modifiers and saved keyboard
preferences unchanged. Fast runs and hardware-keyboard-only focus do not toggle
the keyboard. Restore only on completion or Cancel while the same connection
and presentation remain active; lifecycle retirement, navigation, changed focus
and stale callbacks must not reopen it. Restoration must also work when Cancel
retires a non-cancellable write and when dismissal animation is still running.

Cover the shared timing policy and both remote adapters in native regressions.
Exercise keyboard-visible/hidden progress, completion, Cancel, quick input and
background/connection retirement across Terminal, Screen Sharing and Trackpad
& Keyboard. Inspect actual screenshots for row silhouettes and readable status.
Run managed stable-Xcode builds, native/UI tests and scripts/validate.sh, then
update PR #46 and install the resulting development build on iPhone 18 Pro Max.
