# Host event transport and Accessibility projection

Date: 2026-08-23

## Outcome

The authenticated primary host frame pump can now publish the frozen
`interactive.surface.focusChanged` event on the same ordered write lane as
command replies. It accepts only the exact events channel/kind with a null
correlation identifier after authentication is ready. A send failure stops the
session, and a command envelope cannot enter this API.

The macOS menu-process platform boundary now has a content-minimizing
Accessibility reader and a pure projector. The reader asks only whether the
process is trusted, for the focused element, its role/subrole, global position
and size, and whether its value is settable. It never asks for an element's
value, selected text, title, label, description, identifier, or application
content. Raw roles are immediately reduced to the closed focus categories and
secure text is reduced to a Boolean.

The projector requires a finite, positive focused rectangle fully contained in
the exact active surface input rectangle. It emits only bounded normalized
geometry plus the closed category, editable, and secure flags. Missing trust,
unavailable focus, invalid geometry, partial clipping, or an unaligned surface
falls back closed instead of guessing a crop.

## Verification

- The real classified primary pump rejects a command passed to the event API,
  emits the exact authenticated focus event, and preserves serialized framing.
- Three pure macOS projection tests prove the closed shape and conservative
  normalized bounds, unsafe-geometry Desktop fallback, and invalid-surface
  rejection.
- The repository-wide gate passes 73 indexed fixtures, all 1,485 discovered
  Swift tests, macOS/iOS cross-builds, unsigned permanent application builds,
  and eight platform authority probes on Xcode 27 beta.

This checkpoint does not yet poll or subscribe to live Accessibility focus,
carry a sanitized candidate over authenticated local XPC, bind event creation
to the active Agent product, construct a live ScreenCaptureKit focus crop, or
apply Smart Zoom automatically on iOS. It makes no signed-device, TCC, latency,
or lock-screen claim.
