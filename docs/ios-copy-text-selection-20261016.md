# iOS Copy Text selection — October 16, 2026

Copy Text opens one frozen original-pixel image. Supported, bounded images use
VisionKit Live Text automatically: touch and hold a word, adjust the native range,
and Copy. The optional compact editable review stays beside the source image.
Done explicitly returns to Screen Sharing.

Select Area retains the accurate Vision recognizer for difficult layouts and
unsupported/oversized full images. Its rectangle has accessible resize corners,
a transient magnifier, drag-to-move, local pan/zoom and visible/full-image actions
in More. Recognition starts after adjustment settles and the drag ends; old results become
uncopyable immediately when the area changes. Language, retry, Copy All and
explicit Share actions live in More. Hiding and reopening a native review keeps
corrections until the native selection changes, and Copy uses the retained review.

Native and area analysis are bounded and serialized. Native interaction types
must be applied after assigning the completed analysis; configuring them only
before analysis left the text selectable in neither touch nor UI automation.
Native long-press/copy is now exercised by the dedicated UI journey.

The existing session input suspension, acknowledged held-input release, fresh
frame on return, foreground/replacement checks and privacy retirement remain in
the viewer/session owner. The local tool has no remote-input owner. Background,
lock and connection replacement retire images, text and pending callbacks. No
new network operation, helper, authentication or wire behavior is introduced.
System text-selection menu exports remain explicit user actions. OCR remains
best-effort for code, columns and whitespace.

## Validation

Stable Xcode 27: 21 focused hosted tests passed, including native analysis and
cancellation, canonical availability/bounds, original-pixel cropping, automatic
area recognition, editable copy, large text/layout and session/lifecycle checks.
Three native UI journeys passed on both the dedicated iPhone and iPad Simulators:
word selection/copy without review, area drag/automatic recognition/editing and
rotation with Done reachable, and background snapshot retirement. No skips.

The simulator-only application and UI tests live in Experiments/ScreenTextQA;
`verify_terminal_pro_simulator.py --screen-text-ui --generate-only` adds their
private scheme. They are not linked into the normal app. Synthetic screenshots,
logs and result bundles remain outside Git under
`/private/tmp/maccompanion-copy-text-20261016/`.

Stable `bash scripts/validate.sh` passed. Development build 1.0 (74) was installed
and launched on the user's iPhone 18 Pro Max; the installed bundle version was
read back from the device. Real Screen Sharing acceptance remains for the user
to confirm, separately from simulator results. Cursor investigation remains
paused, and macOS/visionOS do not link this iOS selection adapter.
