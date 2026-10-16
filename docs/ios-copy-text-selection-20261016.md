# iOS Copy Text selection — October 16, 2026

Copy Text opens one frozen original-pixel image. Supported, bounded images use VisionKit
Live Text automatically: touch and hold a word, adjust the native range, and Copy. The
optional editable review opens in a native medium/large resizable drawer, with the
frozen image behind it. The keyboard appears only on editor tap. Native Back and a leading-edge swipe return to
Screen Sharing. The centered title and ellipsis header replace the previous large text
buttons; Text/Area, Review and a prominent Copy form the bottom
controls.

Select Area retains the accurate Vision recognizer for difficult layouts and
unsupported/oversized full images. Its connected rectangle is visible immediately, with
a subtle outside dim and small corner dots retaining 44-point hit targets. It has
accessible resize corners, a transient magnifier, drag-to-move, local pan/zoom and
visible/full-image actions in More. Recognition starts after adjustment settles and the
drag ends; old results become uncopyable immediately when the area changes. Language,
retry, Copy All and explicit Share actions live in More. Hiding and reopening a native
review keeps corrections until the selection changes, including an empty draft, and Copy
uses the retained review. At accessibility text sizes the heading, editor, status and
actions can scroll while Back and More stay reachable. At the largest accessibility
sizes the export actions stack vertically. The native Review drawer handles its keyboard
independently; closing it does not resume remote input.

Native and area analysis are bounded and serialized. Native interaction types must be
applied after assigning the completed analysis; configuring them only before analysis
left the text selectable in neither touch nor UI automation. Native long-press/copy is
now exercised by the dedicated UI journey.

Session input suspension and acknowledged held-input release remain with the viewer/session
owner. Returning from this local tool preserves the current complete live baseline. Real
background/resume, replacement and display changes retain their independent readiness
checks. Remote failure ends transport/activity immediately but preserves the local
snapshot and draft until Back reveals recovery. The local tool has no remote-input owner.
Background, lock and connection replacement retire images, text and pending callbacks. No new network
operation, helper, authentication or wire behavior is introduced. System text-selection
menu exports remain explicit user actions. OCR remains best-effort for code, columns and
whitespace.

## Validation before the compact-modal A follow-up

Stable Xcode 27: 24 focused hosted tests passed, including native analysis and
cancellation, canonical availability/bounds, original-pixel cropping, automatic area
recognition, editable copy, large text/layout and session/lifecycle checks. Four native
UI journeys passed on both the dedicated iPhone and iPad Simulators: word selection/copy
without review, area drag/automatic recognition/editing and rotation with Done
reachable, background snapshot retirement, and largest-text editing/copying while the
keyboard is open. All 32 tests passed; no skips.

The simulator-only application and UI tests live in Experiments/ScreenTextQA;
`verify_terminal_pro_simulator.py --screen-text-ui --generate-only` adds their private
scheme. They are not linked into the normal app. Synthetic screenshots, logs and result
bundles remain outside Git under `/private/tmp/maccompanion-copy-text-20261016/`.

Stable `bash scripts/validate.sh` passed. Initial development build 1.0 (74) was
installed and launched on the user's iPhone 18 Pro Max; the installed bundle version was
read back from the device. Subsequent review fixes were validated in Simulator; the
installed phone build remains 74. Physical acceptance of those follow-ups remains
separate from simulator results. Cursor investigation stays paused, and macOS/visionOS
do not link this iOS selection adapter.

Independent subagent reviews identified lost native corrections, crop reflow during an
active drag, an inaccessible largest-text keyboard layout, and an empty area review that
could not reopen. These were fixed with regression coverage. The final full reviews and
focused layout follow-ups found no remaining actionable issues.

## Compact modal A follow-up

The approved A design replaces the inline review with a native resizable drawer. Area
recognition prepares text without opening Review or focusing the editor.
Closing/reopening or swiping down Review preserves corrections, including empty and
overlong drafts. New selection still retires the old copy result immediately. Closing
Copy Text or backgrounding retires the snapshot, drawer and text. The existing remote-
input release and fresh-frame return gates are unchanged.

Simulator and device validation for this follow-up is recorded separately from the
earlier build-74 results above.

Final follow-up validation: 26 focused hosted tests and four native interaction
journeys on each of the iPhone and iPad Simulators passed (34 total, no skips).
The journeys assert a visible software keyboard with more than 100 points of
height, exercise native selection/copy, area adjustment, Review expansion,
rotation, drawer/background retirement and the largest accessibility text size.
The QA accessibility override is applied to its own window so presented drawers
inherit it; it changes no system preferences and is excluded from the normal app.
Stable Xcode 27 `bash scripts/validate.sh` passed. The normal signed development
app 1.0 (75) was installed on the iPhone 18 Pro Max, its installed bundle version
was read back, and device launch succeeded. Physical feature acceptance is pending.
Evidence is outside Git at `/private/tmp/maccompanion-copy-text-modal-a-20261016/`.
No cursor, credential, transport or macOS/visionOS source changes were made.

## Native navigation B and live return

The iPhone build-75 diagnostic recorded failure stage 102: a local review return
reset the still-live baseline, counted 63.2% fresh coverage after two retries and
hit the eight-second baseline deadline. Returning from Copy Text now clears only
its input-suspension gate. Live updates continue throughout; no new full image is
requested, and Copy Text can reopen immediately on the same valid owner/display.
Actual replacement, resize, background and interruption checks remain independent.

If the remote connection actually fails during extraction, the app ends transport,
shared file borrowing and Live Activity promptly. It preserves the frozen image,
selection and editable text, deferring the recovery card until Back. Background,
lock and explicit exit still clear private image/text content. A deferred failure
that spans inactivity is revealed only after foreground admission; replacement
and explicit exit retire the old error.

The normal iOS view owns a native navigation container with Screen Sharing as its
root and Copy Text pushed above it. Back taps and a leading-edge swipe return to
that same viewer. Full-content Back swipes are disabled so image pan, selection
and crop gestures retain their purpose. Review remains a separate native drawer;
its close gesture preserves the Copy Text page and draft.


Final B validation: stable Xcode 27 passed 59 focused hosted Simulator tests and
five native interaction journeys on each dedicated iPhone and iPad Simulator
(69 total, no skips). Coverage includes a retained socket receiving only a small
incremental rectangle after return and staying healthy beyond the old eight-second
timeout, independent baseline/background/interruption gates, deferred connection
failure with local Copy still usable, repeated opening, native Back/edge swipe,
area adjustment, rotation, visible keyboard and the largest accessibility text size.
Stable `bash scripts/validate.sh` also passed. Synthetic screenshots were inspected;
no user screen or input content was captured.

The normal development app 1.0 (76) was signed with all 615 recorded source inputs
matching the tested checkout, installed on the iPhone 18 Pro Max, read back as
build 76 and successfully launched. Physical feature acceptance remains pending.
Evidence is outside Git at `/private/tmp/maccompanion-copy-text-navigation-b-20261016/`.
Cursor and password-manager investigations remain paused.


### Desktop viewport and frozen-image viewport

The frozen image initially opens around the unobscured remote-screen viewport.
That conversion uses original pixels within the selected-display snapshot; it
does not add the display's framebuffer offset again or multiply by Retina scale.
The viewer-to-review regression checks two zoom levels, asymmetric control insets,
Retina pixels and an offset selected display. Build 76 already had that mapping.

This is distinct from switching Text to Area after zooming or panning inside
Copy Text. That transition previously retained the original desktop rectangle.
It now selects the frozen image viewport visible at the moment Area is chosen,
without changing the local zoom or pan. Every Text-to-Area transition takes a new
visible selection; another Area action while already adjusting a crop keeps that
crop. Selecting the full image remains an explicit More action.

Hosted coverage exercises local zoom/pan, both Text-to-Area transitions and
retaining a custom crop without refitting. Native Simulator coverage performs an
actual pinch and pan before choosing Area. No transport or cursor behavior changes.


Frozen-viewport validation: stable Xcode 27 passed 61 focused hosted Simulator
checks. All six native UI journeys were covered on each dedicated phone and
tablet Simulator across the retained runs. The existing keyboard journey hit
XCTest animation-notification waits in the broad runs, so those runs were
interrupted; the keyboard journeys passed from fresh app launches. The final
viewport journey requires a measured real zoom and compares the selected pixel
width/height with the frozen viewport immediately before choosing Area. On the
tablet, the first synthetic pinch applied no scale change; a larger real pinch
succeeded. The QA-only numeric probe and image accessibility target are excluded
from the normal application. Passing phone and tablet screenshots were inspected.
Stable `bash scripts/validate.sh` passed for the application change.

The normal signed development app 1.0 (77) matched all 615 recorded production
inputs and was installed on the iPhone 18 Pro Max. The installed version was read
back as 77. Automatic launch was denied because the phone was locked; physical
feature acceptance remains pending. Evidence is outside Git at
`/private/tmp/maccompanion-copy-frozen-viewport-20261016/`. Cursor work stays paused.
