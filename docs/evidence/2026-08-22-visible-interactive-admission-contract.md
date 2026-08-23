# Visible Interactive admission contract and authority

Date: 2026-08-22

## Result

The menu-to-Agent visible Interactive admission is now a closed v0.1 contract,
an exact authenticated local-XPC request/ack transaction, and a stable
generation-fenced Agent authority in the permanent product composition. The
menu publishes revision 1 only after readiness acknowledgement and before its
first status read. It says that a visible menu process exists and which opaque
display token, if any, it currently owns; it grants no Control authority by
itself.

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

The permanent Agent creates one authority before primary-service bootstrap.
That same actor is both the visible side of the durable-plus-visible admission
reader and the only handler injected into the presentation-capable XPC server.
Status-only, bootstrap, recovery, and authentication-only profiles cannot
receive it. Transport replacement, malformed traffic, timeout, cancellation,
or loss withdraws the matching generation locally; stale invalidation cannot
remove a successor.

## Production transport

The C bridge accepts only the exact request dictionary and returns only the
exact payload-bearing acknowledgement. Swift gives publication an independent
single-flight transaction gate, so it cannot overlap itself or borrow pairing
command or Agent-to-menu lease ownership. The server authenticates the menu,
requires published readiness, authorizes `publishInteractiveState`, decodes
canonical bytes, invokes the generation-bound authority within three seconds,
and validates the complete receipt before replying. The menu waits at most
four seconds and terminates its XPC generation on any ambiguous send, reply,
correlation, cancellation, or timeout.

## Verification

- The repository fixture validator passes all 67 indexed protocol/product
  fixtures, including the new canonical profile.
- The C exact-message self-test covers the closed request and acknowledgement
  dictionaries, including rejection of an added field.
- Two codec tests cover exact round trips, correlation, unknown fields,
  noncanonical bytes, and the payload ceiling.
- Three authority tests cover replay, exact +1 advancement, display selection,
  skipped revision, changed menu generation, stale invalidation, withdrawal,
  and strictly newer replacement. Additional transport/product tests cover the
  independent generation gate, exact profile injection, and readiness-before-
  publication-before-status ordering.
- The complete package catalog passes 1,413 Swift tests under the supported
  Xcode 27 beta sandbox-disable flags.

## Non-claims

This checkpoint does not enumerate a display or retain a physical-display
mapping. The permanent initial publication therefore carries a nil selected
display and cannot admit Control. It also does not activate capture, media,
input posting, automatic lease renewal, or secondary-channel handoff. The next
checkpoint must add the menu-owned opaque UUID-to-display mapping and publish
an exact +1 revision when that selection changes.
