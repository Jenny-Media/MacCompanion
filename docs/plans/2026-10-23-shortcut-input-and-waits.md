# Shortcut typing, paste and cancellable waits

Add four explicit step choices to the shared iOS shortcut editor: Press Key,
Type Text, Paste Text and Wait. Existing `text` steps keep paste behavior. The
profile format advances to version 4 so older apps preserve unsupported data.

Type Text uses negotiated key encoding without bracketed-paste markers. Return
and Tab remain explicit key steps. Wait defaults to one second, supports
0.1–30 seconds, and the complete shortcut permits at most 60 seconds of waits.

Execution reserves its existing session input owner across the whole sequence.
Waits suspend asynchronously, recheck admission during and after the wait,
cancel on lifecycle retirement, and never replay into a replacement session.
Terminal steps are re-encoded when sent so a program's mode changes during a
wait do not reuse stale keyboard/paste formatting. A running sheet provides
explicit cancellation for sequences with waits. VNC keeps reading/rendering
while waits run and reserves ordinary input until completion/cancellation.

Validate old-step decoding, typed versus pasted UTF-8/negotiated input, exact
order, delay boundaries, invalid durations, cancellation and no replay, plus
remote event/modifier balance. Exercise both user examples in Simulator with
a disposable SSH peer and input recorder, including a delayed numeric prompt
and Ctrl+g → Ctrl+o → d. Capture editor, running/cancel and result screenshots.
Run the managed native tests and `bash scripts/validate.sh` with Xcode.app.
Build and install the resulting development app on the iPhone 18 Pro Max.
No macOS/visionOS feature work or TestFlight publication is included.

Return discoverability: Add Step offers a direct Return action alongside the
four existing step types. The direct action appends an ordinary key step to
the local draft, respecting the step limit and preserving deliberate repeats.
Configuration pickers, sequence previews and reviews show “↵ Return”; runtime
keycaps retain the compact symbol. Both Return and Enter find the same key.
Cover direct insertion, search, modifiers, save/reopen, cancellation and the
existing mixed-step and inline creation flows before installing build 151.
