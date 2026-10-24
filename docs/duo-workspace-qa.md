# Duo workspace validation

The iOS client uses the active UIKit `.division` reserved region. Its frame already includes interactive margins. A horizontal division retains the established Tabletop content/input regions; a vertical division with at least 280 points on each side creates a Book workspace. No orientation, device-name, screen-aspect, or hinge-angle heuristic selects the layout.

In Book, Screen Sharing keeps the remote display on the left and the relative trackpad plus customized keyboard bar on the right. The native connection sheet uses one page at the input edge while retaining its existing form owner; the standalone fallback also keeps its fields together. Terminal keeps its existing terminal instance and buffer on the left and the customized keyboard bar on the right. The shared floating menu stays on the input page. The keyboard reduces usable space; it does not create a new session or send pending text. Layout changes continue to release held pointer input through the existing viewport adaptation path.

The Screen Sharing host leaves keyboard avoidance to its UIKit controller; SwiftUI does not also shrink that controller for the keyboard. The normal session and local sample share this safe-area policy. Automatic reflow keeps the intended crop-relative zoom and center even when an intermediate size temporarily clamps the visible offset. A deliberate user zoom or pan still updates that viewport, and keyboard dismissal retains the existing crop-checked restoration behavior.

Without an active usable division, the ordinary iPhone/iPad layout remains in use. Existing Tabletop Terminal behavior is retained: a closed or hardware-only keyboard leaves the whole terminal usable; an onscreen keyboard reserves the upper content region. New UIKit class resolution stays dynamic and availability guarded so the iOS 26 deployment target and iOS 27.0 launch remain supported.

## Safe local sample

A Debug build can launch with `--duo-workspace-sample`. This opens a labelled local synthetic workspace and never loads or connects a saved Mac. Its session subclass opens no transport, discards all input locally, and stores no input contents. Release builds exclude this entry point. It uses real system regions; it does not fabricate physical posture.

This is suitable for checking reachability, keyboard presentation, and native layout during the grouped physical acceptance session. It cannot establish real Screen Sharing delivery, SSH behavior, connection lifetime, or remote application consumption.

## Automated checks

Run the existing native QA generator using an isolated build/cache and an explicitly owned Simulator. Relevant suites are `VNCKeyboardHostingTests`, `AdaptiveLayoutTests`, `TerminalDuoLayoutTests`, `ViewportTests`, `TextComposerTests`, and `SessionLifecycleTests`. The new cases cover vertical region admission, frame margins, viewport/owner continuity, balanced local pointer events, retained login fields, menu reachability, retained terminal output, and real hosted keyboard presentation on an iPad Book geometry fixture. Ordinary iPhone keyboard tests remain separate from the iPad Book geometry fixture.

Run `bash scripts/validate.sh` before handoff. Results from the installed Xcode 27.1 toolchain do not establish the separate stable Xcode lane.

## Physical acceptance

Keep this PR in draft until the grouped five-app session records all ten landing positions: closed portrait and both landscape directions, fully open portrait and both landscape directions, both Book directions, and both Tabletop resting halves. Record actual OS orientation and active system region separately from the owner's posture confirmation. Preserve earlier captures.

Cover the connection sheet, remote view, keyboard toggle and custom controls, trackpad click/drag/scroll, control-menu reachability, foreground/background transition, and transitions among closed/open/Book/Tabletop while retaining the same session and pending input. The local sample can prove only layout. A real session requires the owner to configure a Mac and explicitly approve any remote input; no live-session pass is implied by synthetic tests or screenshots.

Comparison PNGs, typed/input logs, credentials, signing material and profiles must remain outside this application repository, as required by `AGENTS.md`.
