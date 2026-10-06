# iPhone Duo support: research and recommended work

Reviewed 2026-10-06. Research and planning only; Duo behavior has not been tested
in this checkout. The direct Screen Sharing/SSH product remains unchanged.

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

- `CompanionVNCViewer` constrains interactive UI to safe areas and computes fit
  from canvas bounds. It already handles view-size changes without starting a
  new connection. Its resize path preserves fit, but does not explicitly capture
  and restore the normalized viewport center/zoom ratio for every geometry change.
- `CompanionVNCControls` is a custom floating panel with manual positioning.
  It accounts for separate left/right safe insets, but has no reserved-region
  handling. The custom horizontal modifier row also needs a narrow/short layout.
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
device type, and available iOS 27.1 runtimes. No Mac Companion Duo run or
acceptance is claimed. Stable Xcode 27.0 remains the required verification lane;
new SDK-only work needs the stable 27.1 lane before its results are final.

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
