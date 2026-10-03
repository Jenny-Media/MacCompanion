# App window selection and native switching time

## Diagnosis

Application capture includes the selected application's on-screen layer-zero
windows on the selected display. The capture rectangle is their union, with
24 points of padding clipped to that display. The application filter preserves
window positions; it does not pack windows together. Several separated windows
therefore produce a wide canvas containing blank gaps. This explains the
reported Xcode Device Hub layout when several Xcode windows were open.

The current native selection path fences and drains input, closes the renderer
and enrollment, obtains the replacement surface, creates a new TLS identity and
native enrollment, launches the stream, and acknowledges its first presentation
before admitting input. There is no deliberate multisecond smoothing wait.
The five-second Debug frame-progress monitor runs after video starts and does
not hold view selection.

Four completed switches in the final resize-recovery Simulator run took:

| Stage | Observed duration |
| --- | --- |
| Input fence, old stream drain, replacement surface acknowledgement | 0.34–0.77 seconds |
| Replacement start through native enrollment | 1.39–2.04 seconds |
| Enrollment through successful launch response | 0.40–0.85 seconds |
| Launch through first presentation and input acknowledgement | 0.29–0.63 seconds |
| Complete switch | 2.95–4.02 seconds |

These are Simulator observations, not measurements of the user's iPhone. The
samples come from `/private/tmp/maccompanion-normal-resize-desktop-recovery-qa-v2-20261002/content-free-runtime-diagnostics.log`,
starting at timestamps 1790991651.487, 1790991662.128, 1790991676.834 and
1790991681.427. A failed earlier run in the retained log is excluded.

## Picker change

- Selecting an app with multiple available windows opens a window chooser
  without issuing a surface-selection command or changing the current stream.
- Selecting an app with one available window selects that window's existing
  opaque target token and `window` kind directly.
- The chooser has an explicit **All App Windows** option with an explanation
  that their Mac positions and blank gaps are retained.
- Window association uses the opaque application token, not an app name.
  Unavailable windows are omitted. Refresh returns to the root picker and
  discards destinations associated with the replaced inventory tokens.
- The UI harness presents the picker as a sheet, matching the normal app.

This is a client presentation change. It uses the existing App/Window inventory,
selection protocol and capture semantics.

## Verification

Stable Xcode 27.0, build 27A266a:

- `bash scripts/validate.sh` passed, including the new opaque window-association
  regression and all 118 indexed fixtures.
- The Simulator UI test `testAppSelectionChoosesWindowBeforeChangingSurface`
  passed. It verifies app navigation does not select a surface, only that app's
  windows appear, selecting a specific window emits `window`, Refresh returns
  to the root picker, and explicitly selecting all windows emits `application`.
- Initial harness attempts exposed nested navigation and an accessibility label
  replacing the result text; both harness issues were corrected before the
  passing interaction test.

Private logs:

- `/private/tmp/maccompanion-app-window-picker-stable-validation-20261002.log`
- `/private/tmp/maccompanion-app-window-picker-final-stable-validation-20261002.log`
- `/private/tmp/maccompanion-app-window-picker-ui-v3-20261002.log`

The source-verified normal iOS development app was signed using the existing
identity, unchanged signed entitlements and existing device profile. It was
installed in place on the paired iPhone 18 Pro Max and launched successfully;
the device inventory confirmed `media.jenny.maccompanion.ios`, version 0.1.0,
build 1. The update did not uninstall the app or alter pairing material.

- Native/iOS source input: `e375f2536d5d99c4aa54382b320c69b42463dcf3854aff66df9022f8890a86b9`.
- Signed iOS executable: `f1c97503cae0c53aca732b6ac47b8e4f0587b9fe0d00eb3142c450b180daeca3`.
- Private installation receipt:
  `/private/tmp/maccompanion-app-window-picker-iphone18-install-20261002.json`.
- Private signing receipt:
  `/private/tmp/maccompanion-app-window-picker-iphone18-signature-20261002.json`.

Physical Xcode Device Hub acceptance remains pending. This change does not
reduce stream replacement time, compose multiple windows into a new layout,
or implement continuous window resizing.

## Next performance change

Reuse the native connection and owned host across surface changes, update
capture content and geometry, then admit input only after a fresh presentation
acknowledgement for the selected surface. Reusing a fixed encoded canvas may
avoid decoder reinitialization when window sizes differ. That requires a
specified reconfiguration path, authoritative fixture coverage, and stale
frame/input rejection; skipping the current fences is not a valid shortcut.

No fast reconfiguration or measured physical latency improvement is claimed
by this checkpoint.
