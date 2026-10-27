# Keyboard key previews in iOS 1.1

The shared Terminal, Screen Sharing and Trackpad & Keyboard row bar shows an
enlarged label or symbol immediately on finger-down. A successful quick tap
keeps the passive echo visible for at least 120 ms from finger-down; this does
not delay the key's touch-up input. Starting another key replaces the old echo.
Sliding away, scrolling, cancellation, disabling a key, removing it from the
window, moving its layout or leaving the active app dismisses the preview
immediately, including a pending quick-tap echo. The scroll view delivers
touch-down without its normal content delay and retains button-touch
cancellation for pans. The bubble stays within the bar's horizontal pane,
including narrow Duo panes.

The existing touch-up action remains the only input action. Showing a preview
does not send input or consume an armed modifier. Modifier one-shot and long
press locking behavior remains unchanged. Keyboard visibility, keypad / row
expansion and layout-editor controls retain their normal pressed appearance.
VoiceOver uses the existing key accessibility labels without a visual echo.

`RemoteMacControlsTests/testKeyPreviewIsPassiveCancelsAndKeepsExistingInputAdmission`
covers a visible preview, cancellation, re-entry, release, disabled controls,
execution blocking, backgrounding, removal and one balanced remote key delivery.
The existing modifier, rejected-admission, toolbar and layout regression tests
remain applicable. Synthetic Simulator screenshots are test evidence outside
application Git. They are not physical iPhone, iPad or Duo acceptance; physical
Duo evaluation uses a future TestFlight candidate.

Active previews also dismiss when their containing pane’s usable bounds change,
even if the pressed key keeps the same window rectangle. The native regression
checks a narrower pane with a fixed key and verifies that no input is sent.

Quick-tap regressions cover visible release, expiry, replacing a held key,
cancelling pending dismissals and immediate scroll-view touch delivery.
The opt-in TerminalControlsQA native UI journey uses real short presses and a
drag starting on a key. A display-link probe in that synthetic harness records
rendered preview frames; the journey verifies a balanced key on a successful tap
and no key on a scrolling cancellation. These probes are absent from the normal
application.
