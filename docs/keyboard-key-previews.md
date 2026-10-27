# Keyboard key previews in iOS 1.1

The shared Terminal, Screen Sharing and Trackpad & Keyboard row bar shows an
enlarged label or symbol while an input key is pressed. Sliding away, cancellation,
release, disabling a key, removing it from the window, moving its layout or
leaving the active app dismisses the preview. Scroll views retain their existing
button-touch cancellation behavior. The bubble is passive and stays within the
bar's horizontal pane, including narrow Duo panes.

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
