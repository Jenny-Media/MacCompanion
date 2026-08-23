# Ordered focus-event lane and client admission

Date: 2026-08-23

## Outcome

The authenticated application-primary stream now has one closed unsolicited
event profile for privacy-limited focus assistance. The normative
`interactive.surface.focusChanged` message uses `channel: "events"`, null
correlation, an independent exact sequence, a connection replay window, and a
Control-only receiver. It cannot resolve, consume, or delay an Observe, Act, or
Control command reply.

The event contains only the current acknowledged surface fence, a recommended
Focused Region or Desktop target, a short-lived opaque target token, and the
closed focus projection: token, revision, category, bounds, editability, and
security state. Labels, values, selections, placeholders, titles, paths, URLs,
thumbnails, and OS identifiers remain outside the schema.

## Client authority boundary

The client admits the event only for the exact active Interactive session,
authorization epoch, currently acknowledged surface and coordinate revisions,
and next event sequence. Relative validity is materialized against the local
monotonic clock. A duplicate, gap, stale fence, malformed focus projection, or
expired event closes the Control path.

A Focused Region token is current-event-only and one-use. It can enter only the
existing replacement-surface exchange: reliable reset, correlated selection,
configuration and visibly rendered clean frame, exact acknowledgement, and
host-confirmed input resumption. The event itself never changes the surface or
reactivates input. When the host says input is paused, the client rejects local
input while still permitting the exact recovery selection or Control end.

The real primary router integration proves that a valid focus event can
interleave with command traffic, updates the replacement coordinator, and is
published outward only after the router confirms its connection generation is
still current.

## Verification

- The fixture validator accepts 73 indexed canonical fixtures, including one
  valid focus event and one privacy-leaking invalid event.
- All 27 Interactive Wire tests, 8 primary-router tests, 6 replacement-surface
  coordinator tests, and 3 interactive-primary-channel integration tests pass.
- The repository-wide gate passes all 1,477 discovered Swift tests, macOS/iOS
  cross-builds, unsigned permanent application builds, and eight platform
  authority probes.

This checkpoint does not claim a live macOS Accessibility observer, host token
issuer, automatic iOS Smart Zoom application, real ScreenCaptureKit crop,
posted input, focus-latency result, signed installation, TCC consent, or
physical-iPhone evidence. Those remain subsequent implementation/evidence
gates; manual visual zoom remains the working fallback.
