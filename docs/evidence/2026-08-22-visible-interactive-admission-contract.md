# Visible Interactive admission contract and authority

Date: 2026-08-22

## Result

The menu-to-Agent visible Interactive admission is now a closed v0.1 contract
with strict canonical messages and a stable generation-fenced Agent authority.
This gives the later permanent composition one exact way to say that a visible
menu process exists and which opaque display token, if any, it currently owns.
It grants no Control authority by itself.

## Closed publication

`LocalInteractiveAdmissionPublicationV1` contains only:

- the exact local-IPC protocol version;
- a command UUID;
- one opaque menu-process UUID;
- a positive safe-integer revision; and
- an optional opaque selected-display UUID.

The selected-display value is not a `CGDirectDisplayID`, display name, geometry,
window identity, process identity, or permission result. Nil explicitly means
the menu is visible but no display is selected, so Control remains unavailable.

The exact success receipt repeats and correlates every fact. Both values use
strict closed canonical JSON with a 4,096-byte ceiling. The indexed transport
profile fixes one in-flight publication, revision 1 for a new authenticated
transport generation, exact +1 replacement, three/four-second receiver/sender
deadlines, and generation termination on ambiguity.

## Stable Agent authority

`AgentVisibleInteractiveAdmissionAuthorityV1` accepts the first publication
only from a strictly newer nonzero transport generation. Exact replay returns
the retained receipt. A replacement must retain the menu-process UUID and
increment its revision exactly once. Transport invalidation removes only the
matching current generation, so a late callback cannot withdraw its successor.

Its `VisibleInteractiveAdmissionReadingV0` snapshot is the narrow source joined
with durable SQLite device/grant state by the existing conservative admission
reader. No durable security fact is stored or inferred here.

## Verification

- The repository fixture validator passes all 67 indexed protocol/product
  fixtures, including the new canonical profile.
- Two codec tests cover exact round trips, correlation, unknown fields,
  noncanonical bytes, and the payload ceiling.
- Three authority tests cover replay, exact +1 advancement, display selection,
  skipped revision, changed menu generation, stale invalidation, withdrawal,
  and strictly newer replacement.
- The complete package catalog passes 1,411 Swift tests under the supported
  Xcode 27 beta sandbox-disable flags.

## Non-claims

This checkpoint does not add the request to the production XPC C bridge, send a
publication from the permanent menu, enumerate a display, or retain a physical
display mapping. No XPC session, listener, capture, or input path was started.
The next checkpoint must implement the exact request/ack transport and bind its
generation invalidation to this authority before any platform display adapter
is composed.
