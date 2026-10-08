# iPhone Duo support: research and recommended work

Reviewed 2026-10-06. The first adaptive layout pass is implemented and captured
on an isolated Duo Simulator. Physical Duo acceptance remains pending. The
product continues to connect directly to built-in Screen Sharing and SSH.

## Official guidance

Apple recommends preserving functionality and state across the inner and outer
displays, adapting to size classes and available space, and avoiding large
unnecessary rearrangements. Standard containers adapt to the fold and camera
regions; custom UI needs explicit consideration. See
[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

Building with the iOS 27.1 SDK enables the full available display area and new
bar behavior. Layout should use scene/view bounds and size classes rather than
device identity, orientation assumptions, or `UIScreen.main`. Safe areas and
margins can differ on each side, including in Split View. See
[Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

System navigation containers manage vertical bars. Give toolbar items symbols
and titles, group related actions, and prioritize important actions when space
is limited. Keyboard accessory controls remain attached to the keyboard.
Custom bars do not gain automatic vertical adaptation merely by rebuilding.
See [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/).

Reserved regions describe divisions such as the active fold and occlusions such
as cameras. `ArrangementView` and `UIArrangementViewController` can arrange
existing primary/secondary content around these regions. Use layout APIs for
layout instead of continuously deriving it from hinge angles. See
[Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)
and [Multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/).

Multiple app instances are supported when an app adopts multiple scenes, with
new-window availability differing between the displays. The simultaneous outer
display camera accessory requires an active camera capture experience; it is
not a general remote-desktop second screen. See
[Multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/).

## Current code audit

- The baseline viewer computed fit from canvas bounds, but its desktop and login
  used full window width. The adaptive pass constrains them to independent safe
  edges and preserves normalized viewport center and zoom relative to fit across
  local geometry changes. An interrupted drag is released; resizing does not
  start or replace a session.
- `CompanionVNCControls` accounts for separate safe insets and now bounds its
  panel within the lower region of a suitable horizontal system division. The
  modifier row scrolls when it cannot retain 44-point key widths.
- A suitable active horizontal division creates a desktop above and a dedicated
  relative trackpad below. The desktop's selected pointer mode is retained.
  Small/vertical divisions keep the normal layout. Keyboard overlap and the
  immersive mode remain supported.
- Terminal now respects independent horizontal safe edges and continues to
  resize its existing PTY through its existing delegate.
- My Macs and settings use `NavigationStack` and system sheets. The larger
  display currently expands the list rather than providing an optional sidebar.
- VNC coordinator lifecycle observers use application-wide notifications.
  Terminal stops on view disappearance and pauses on application resignation.
  These are audit points for display/scene transitions, not confirmed Duo defects.
- The optional privacy lock keeps one cover window selected from connected
  scenes. Multi-window support needs explicit per-scene protection and session
  ownership before admission.
- Terminal already forwards changed rows/columns to its existing SSH PTY.
  Geometry adaptation should retain that authenticated connection.

Locally installed: Xcode 27.1 RC, build 27A9275, the iPhone Duo Simulator
device type, and available iOS 27.1 runtimes. The comparison uses a dedicated
`Mac Companion Duo QA` device. Stable Xcode 27.0 remains the required verification
lane; new SDK-only work needs the stable 27.1 lane before its results are final.

## First implementation and comparison

The hosted, opt-in `DuoComparisonTests` renders production views with synthetic
content. Device Hub controls the actual pose; the test does not fabricate safe
areas or reserved regions. `verify_terminal_pro_simulator.py --duo-review` runs
only this capture harness. It never connects to a Mac or loads saved logins.

The comparison contains 56 unmodified PNGs: before/after seven screens in four
poses (outer landscape, inner wide, inner tall, tabletop). Matching pairs have
equal bounds and safe insets in their `geometry.json`. Captures stay outside Git.
Baseline production sources are frozen at `bcf3a6d`; the same synthetic harness
is used for both builds. My Macs/settings/SSH setup remain reference surfaces.

`AdaptiveLayoutTests` checks repeated resizing with the same session owner,
viewport focus and zoom, interrupted drag release, two usable tabletop regions,
relative lower-trackpad input while the desktop remains in pointer mode, and
minimum touch targets on narrow modifier rows. The iOS 27.1 APIs are compiled out
when using an older SDK and runtime guarded in the new lane.

Verification of the completed local pass:

- Stable Xcode 27.0: `bash scripts/validate.sh` passed. The full direct-client
  Simulator suite passed 108 tests, with five opt-in capture tests skipped;
  OpenSSH export and sandboxed key-setup interoperability checks also passed.
- Xcode 27.1 RC on the dedicated Duo Simulator: all 28 targeted adaptive-layout,
  session-controls and StoreKit tests passed. RC results remain provisional until
  the stable 27.1 lane passes. The trial-refund test now waits for asynchronous
  transaction delivery before asserting revocation, matching the existing
  lifetime-refund test; production entitlement behavior is unchanged.
- The seven adaptive tests include a tall keyboard covering the lower tabletop
  region: desktop and menu remain above the keyboard, and the trackpad hides
  without acquiring a negative frame.
- The final validation retry passed after an earlier disk-space failure.
  Build caches from this task were cleaned; capture evidence was preserved.

The first-pass evidence did not include actual software keyboards, larger text,
dark recovery views or the complete production Terminal navigation. The
refinement below fills those capture gaps. Multiple app windows are not enabled
by this layout pass. The existing system My Macs navigation is retained.

## Refinement after screenshot review

The approved follow-up is implemented:

- Short landscape uses side-by-side account fields, a smaller identity row and
  adjacent Cancel/Connect actions. Cancel remains interactive while connecting.
  The password visibility control has a 44-point target and an explicit
  accessibility label. Invalid-login feedback remains visible and wraps fully.
- Tabletop places login identity above the active system division and the form
  below it. When a tall software keyboard consumes the lower region, the form
  moves into the usable upper region instead of being covered.
- Terminal keeps its output above a suitable active division and offers Show
  Keyboard below it. The existing terminal buffer, session owner and PTY resize
  delegate are retained. The lower action wraps with accessibility text sizes.
- The floating menu keeps the Mac name fixed. In normal usable space, its three
  category actions stay fixed above scrolling quick actions. Short keyboard
  layouts, narrow widths and accessibility sizes use full-width scrolling rows.
  Tap-open menus survive canvas resizing; an interrupted press-and-slide is
  cancelled without executing an action at a stale position.
- Recovery cards now have an opaque system background below the severity tint.
  Real light-mode captures exposed unreadable text over the dimmed desktop.
- The direct client build declares the scene lifecycle required by its existing
  SwiftUI `WindowGroup`. It admits one application scene. The prior missing
  manifest produced a runtime warning; the new build no longer emits that warning.
  The authoritative build script generates this manifest; legacy target plists
  and protocol behavior are unchanged.

The curated refinement gallery contains 137 unmodified PNGs and is available locally at
`http://127.0.0.1:4186/iphone-duo-refinement-review/`. Capture artifacts and their
provenance manifest live outside Git in the task visualization directory. The
comparison uses the first adaptive pass versus the refinement with matching
bounds and safe insets in all four poses. Terminal's first-pass controller omitted
navigation and the accessory; the refined capture uses the production view.

System-display captures include the actual software keyboard in outer landscape,
inner wide/tall and tabletop, plus dark mode, Accessibility Extra Large, desktop
and Terminal recovery, and invalid-login feedback. The synthetic opt-in harness
does not load saved credentials or connect to a Mac. Software-keyboard capture
settling is confined to that harness and adds no production delay.

Final verification and remaining acceptance:

- Stable Xcode 27.0 direct-client QA: 119 tests, five opt-in capture tests skipped,
  zero failures; OpenSSH encrypted export and key-setup interoperability pass.
- Xcode 27.1 RC on the dedicated Duo: the same 119-test suite passes with five
  opt-in capture tests skipped and zero failures, including OpenSSH interoperability.
- The required `bash scripts/validate.sh` and `git diff --check` pass.
- New SDK-only behavior remains provisional until stable Xcode 27.1 verification.
- Actual Split View on either display remains **unverified**. Device Hub's
  available controls did not produce a side-by-side app arrangement. Reduced-width
  layout tests are not evidence of actual Split View acceptance.
- Physical Duo, live fold/unfold while connecting or typing, and the per-scene
  privacy/lifecycle audit remain pending. This pass does not admit additional
  simultaneous application windows.

## Terminal space and regular iPhone refinement

- Closed keyboards leave the full usable Terminal area available, including both
  tabletop regions. An onscreen keyboard reserves the upper region when a
  horizontal division is active. Hardware-only input leaves the area available.
- Full Screen hides the Terminal navigation bar. One 44-point floating menu
  exposes keyboard visibility, Exit Full Screen and Done alongside existing
  settings. Recovery restores normal navigation automatically. The terminal view,
  buffer and SSH session remain mounted through presentation changes.
- Short, wide login layouts place identity and credentials side by side, with
  account/password fields in one row and Connect before secondary guidance.
  Accessibility text uses a stacked form. Apple's
  [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)
  preserves field identity and focus as the layout changes with keyboard, fold,
  window size or text size.
- Terminal baseline screenshots were recaptured using the production
  `DirectTerminalView` at `bcf3a6d`. The prior bare-controller images omitted
  navigation and were not a fair comparison. The self-contained local page at
  `http://127.0.0.1:4186/iphone-duo-before-after.html` now contains 34 pairs / 68
  unmodified screenshots. It adds keyboard/fullscreen comparisons and regular
  iPhone landscape. Bounds and safe edges match within each new pair; the outer
  Terminal recapture uses the opposite landscape direction to the original set.
  A provenance manifest accompanies the page outside Git.
- Hosted tests cover closed/open keyboard geometry, retained terminal/session
  identity, fullscreen recovery, and login focus through compact/large-text
  layouts. Cursor-follow checks now derive movement from the visible viewport;
  their old fixed movement remained visible in landscape and did not exercise
  the behavior they asserted. No cursor-follow production behavior changed.
- The regular iPhone Simulator's actual menu was used to enter and leave Full
  Screen; navigation restored and the synthetic terminal buffer remained visible.
  This is Simulator evidence, separate from live SSH or physical Duo acceptance.
- Final stable Xcode 27.0 and Xcode 27.1 RC QA each passed 121 tests, with five
  opt-in capture tests skipped and zero failures. OpenSSH interoperability and
  `bash scripts/validate.sh` also passed. RC evidence remains provisional.

## Recommended sequence

### 1. Establish a Duo baseline

Build the existing client with Xcode 27.1 in an isolated Simulator lane. Capture
synthetic UI in outer/inner portrait and landscape, partial fold, tabletop, and
Split View on both sides. Check login, recovery, saved-logins, SSH setup, settings,
desktop, terminal, display picker, keyboard, fullscreen and privacy cover.
Keep iOS 26 compatibility with availability checks for new APIs.

### 2. Make resizing reliable before adding layout features

Keep session ownership stable as presentation geometry changes. Preserve selected
Mac/display, normalized viewport center, zoom ratio, input mode and terminal
contents. Distinguish local canvas resizing from remote framebuffer/layout
changes: folding should not create a new VNC/SSH connection. Fit mode refits;
zoomed mode keeps its focus with valid bounds. Release any interrupted held input
and map gestures using current canvas coordinates.

Test repeated transitions while connecting, typing, dragging and recovering.
Assert connection count stays unchanged for pure layout transitions; verify
cursor mapping and that no unexpected key/button remains down. Actual suspended
or lost sockets still use the existing bounded recovery behavior.

### 3. Adapt controls and presentations

Use system bars for navigation/settings/terminal controls and a single overflow
menu. Keep press-and-slide as a first-class desktop action, with safe reachable
placement around reserved regions and equivalent tap/accessibility access.
Keep the keyboard accessory with the keyboard; provide scrolling/overflow where
the modifier row cannot fit. Check floating/docked keyboards and avoid hiding
useful content behind the fold or camera.

### 4. Add a focused tabletop layout

My product recommendation is desktop/terminal content above and existing trackpad,
keyboard and quick actions below when a suitable horizontal division is active.
Use arrangement/reserved-region APIs; preserve access to the same actions in all
poses. Offer the existing immersive/fullscreen mode. A My Macs sidebar can follow
once continuity is proven; keep the active session stable when navigation adapts.

### 5. Verify privacy and release assets

Check the privacy cover and authentication transitions on every presented scene,
then review whether multiple simultaneous app windows are in scope. Verify
Dynamic Island compact/expanded layouts and Resume/End Session targeting on Duo.
Run light/dark, Dynamic Type, VoiceOver, Reduce Motion and Reduce Transparency
checks. Add current App Store screenshot assets after the UI is accepted, using
[Apple's Duo readiness resources](https://developer.apple.com/iphone-duo/).

Simulator acceptance should precede physical fold/unfold and multitasking smoke
tests. Passing those checks is separate from public distribution admission.
