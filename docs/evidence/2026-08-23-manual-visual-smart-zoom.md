# Manual visual Smart Zoom fallback

Date: 2026-08-23

## Outcome

The permanent iOS live Control screen now offers a local **Zoom** tool for the
current Desktop, Application Focus, or Window Focus pixels. The user explicitly
pinches directly from Fit through 4x without entering an adjustment mode,
pans the magnified viewport with two fingers only within the
visible pixel extent, can return to Fit, and explicitly finishes adjustment
before remote gestures resume.

This is the manual visual fallback required by the Smart Zoom design. It is not
yet focus-assisted Smart Zoom: it sends no focus event or Accessibility
metadata, creates no focused-region host surface, and makes no claim about a
remote field's label, value, selection, or content.

## Input and lifecycle boundary

Entering adjustment mode resigns the stateless software keyboard, emits the
ordinary reset through the existing reliable-input producer, discards the
current gesture mapper. One-finger pointer input remains independent; a
two-finger pan is remote scrolling at Fit and local viewport movement while
magnified.
Remote tap, pointer, scroll, and drag recognizers cannot begin in that mode.

After adjustment ends:

- direct-touch points pass through the exact inverse local scale/translation
  before the existing aspect-fit mapper produces normalized host coordinates;
- trackpad pointer and drag deltas are divided by the visual scale so the
  rendered cursor does not become artificially fast;
- remote scrolling remains an intentional remote content action rather than a
  visual-transform operation; and
- surface replacement, Control disable/close, encoded-dimension change, and
  viewport-size change reset to Fit before interaction continues.

The transform changes only the UIKit video presentation. It does not advance a
host surface or coordinate revision, replace the authority fence, open another
channel, or create a second input path.

## Why focus push remains separate

The current primary command owner is a strict correlated request/reply channel.
Treating an unsolicited `interactive.surface.focusChanged` message as a reply
would weaken its closed direction and correlation rules. Automatic
focus-assisted framing therefore remains fixture-first work behind an explicit
ordered event-lane design; it is not smuggled through this local fallback.

## Verification

- Three pure transform tests cover anchor-stable inverse mapping, inverse
  trackpad deltas, pan clamping, Fit reset, and invalid geometry/scale.
- All 48 `CompanionInteractiveClientTests` pass.
- `CompanionClientUI` cross-builds for `arm64-apple-ios17.0-simulator`.
- The unsigned disposable `ClientUIHarness` builds as a universal Simulator app
  for `arm64` and `x86_64`, compiling the production UIKit gestures and SwiftUI
  Zoom controls.
- The repository-wide gate passes 71 indexed fixtures, the 1,471-test Swift
  catalog, macOS/iOS cross-builds, unsigned permanent application builds, and
  all eight platform probes.

No signed installation, physical-iPhone gesture/render exchange, real
ScreenCaptureKit pixels, posted macOS input, focus latency, or lock-session
behavior is claimed by this checkpoint.
