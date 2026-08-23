# Live Focused Region Smart Zoom

Date: 2026-08-23

## Outcome

The permanent Control path now turns the authenticated, privacy-filtered focus
event into a real Focused Region capture and applies it automatically on iOS.
It does not add a second control authority: the Agent-issued one-use target is
still consumed before the menu process resolves a source, and the client still
uses the ordinary reset, select, discontinuity, decoder-configuration, clean
rendered frame, acknowledgement, and input-resumption exchange.

The menu re-reads the current reduced Accessibility observation immediately
before resolving the crop. Exact global focus geometry and the closed
category/editable/secure tuple must still match the observation that produced
the event. The crop adds bounded context, clamps to the source display, retains
global logical bounds for input mapping, and translates only the
`SCStreamConfiguration.sourceRect` into display-local logical coordinates.
Capture dimensions apply the owning display's point-to-pixel scale and remain
inside the existing 1,920 by 1,200 and pixel-count limits.

ScreenCaptureKit ignores `sourceRect` for a desktop-independent single-window
filter. Window Focus therefore retains a second, menu-private display filter
limited to the owning application for a later Smart Zoom crop; ordinary Window
Focus itself continues to use the single-window filter. Application and
Desktop sources retain their display-style filters directly. No filter,
physical display identifier, process identifier, raw Accessibility object, or
global rectangle crosses local IPC or the public network protocol.

## Client behavior and races

The selected-primary publication relay now carries admitted focus events to
the exact current Interactive role product. An event arriving after the first
surface acknowledgement but before product-state promotion is retained once
for that exact connection and applied after promotion. Re-enabling automatic
follow consumes the channel's latest still-current event, closing the inverse
race where local policy changed after event admission.

The live UIKit product disables input and its software keyboard across every
automatic transition, updates the authoritative descriptor and render
dimensions only after the replacement acknowledgement, and reenables input
only on success. **Follow Focus Automatically** is enabled by default. Any
manual Desktop, Application, or Window selection disables it before beginning
the transition; the user can explicitly enable it again. Invalid, expired,
stale, ambiguous, or failed transitions converge through the existing
fail-closed Control teardown.

Stable focus identity uses only menu-private global geometry plus the reduced
closed attributes. A coordinate-space change caused by the crop cannot invent
a new focus merely because the same field has different normalized bounds in
the smaller surface. A genuinely changed or missing focus inside an existing
Focused Region still pauses input and recommends the next crop or Desktop
fallback.

## Verification

- Five pure crop tests cover context, nonzero display origins, edge clamping,
  bounded large crops, unsafe/out-of-source rejection, and concrete
  `SCStreamConfiguration.sourceRect` assignment.
- A client activation test proves policy opt-out, automatic Focused Region
  selection through the existing replacement exchange, exact one-use token
  forwarding, and manual-selection opt-out.
- Existing ordered-event, selected-primary, focus-observer, replacement-media,
  input suppression, and runtime-transition suites remain green.
- The repository-wide gate passes 73 indexed fixtures, all 1,499 discovered
  Swift tests, macOS/iOS cross-builds, unsigned permanent application builds,
  and eight platform authority probes on Xcode 27 beta.

This is bundle-independent construction evidence. Signed two-process TCC
execution, real ScreenCaptureKit crop pixels, physical-iPhone automatic focus
latency and usability, multi-display/window-edge behavior, lock behavior, and
stable Xcode 26.6 release evidence remain open.
