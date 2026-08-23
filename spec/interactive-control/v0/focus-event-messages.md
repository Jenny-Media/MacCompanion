# Interactive Control focus-event messages v0.1

Status: normative closed JSON schema for the authenticated application-primary
event lane. This lane publishes privacy-limited focus candidates; it neither
changes a surface nor resumes input by itself.

## Event envelope and ordering

`interactive.surface.focusChanged` uses the ordinary seven-field capability
envelope with `channel: "events"` and a null `correlationID`. It is a host-origin
event, not a command reply. No other v0.1 message is admitted on the event lane.

The body carries a positive safe-integer `eventSequence` independent of the
server command-response sequence. It starts at 1 for each accepted Interactive
session on its exact authenticated primary connection and advances by exactly
one. The host may coalesce unassigned Accessibility callbacks, but it may not
drop, replace, or reorder an event after assigning its envelope message ID or
sequence. The client admits the event message ID through the connection replay
window and requires the exact next event sequence. A duplicate, rollback, gap,
unknown kind, wrong channel, non-null correlation, or invalid body ends the
Interactive session.

There is deliberately no cross-connection event resume in v0.1. Loss or
replacement of the authenticated primary connection already ends its
Interactive session, invalidates every focus candidate, and resets the next
session's event sequence to 1. A future resumable Interactive session requires
a new protocol version with an acknowledged event cursor and bounded replay;
it may not infer continuity from a new TLS connection.

Command replies and events may interleave on the primary byte stream. The
client router keeps their replay/order state separate: a command reply resolves
only its exact pending request, while an event routes only to the installed
Control event receiver. Neither path may consume or satisfy the other.

## `interactive.surface.focusChanged`

The body has exactly these fields:

- `interactiveSessionID`: canonical UUID for the active Control session.
- `authorizationEpoch`: positive safe integer for the authenticated device.
- `currentSurfaceID`: exact currently acknowledged surface UUID.
- `currentSurfaceRevision`: exact positive current surface revision.
- `currentCoordinateSpaceRevision`: exact positive current coordinate revision.
- `recommendedTargetKind`: `focusedRegion` or `desktop` only.
- `targetToken`: a canonical opaque UUID for `focusedRegion`; null for Desktop.
- `focus`: the permitted focus projection for `focusedRegion`; null for Desktop.
- `inputPaused`: whether the host closed input admission and released retained
  input before publishing this event.
- `reason`: one of `verifiedFocus`, `noVerifiedFocus`,
  `accessibilityUnavailable`, `ambiguousGeometry`, `systemSurface`, or
  `targetDisappeared`.
- `validForMilliseconds`: integer from 1 through 2,000.
- `eventSequence`: positive safe integer.

The focus projection has exactly `token`, positive safe-integer `revision`,
closed `category`, normalized `bounds`, `editable`, and `secure`. It reuses the
surface descriptor's closed projection. Labels, values, roles beyond the
closed category, selections, lengths, placeholders, descriptions, application
or window titles, paths, URLs, thumbnails, and OS identifiers are forbidden.

`focusedRegion` requires a non-null token and focus plus
`reason: "verifiedFocus"`. Desktop requires both to be null and a non-verified
reason. Relative validity is materialized against the receiving client's
monotonic clock; host wall or monotonic focus timestamps never cross devices.

## Selection correlation and authority

An event does not select, acknowledge, or activate a surface. A focused-region
`targetToken` is random, session-scoped, bound server-side to the exact event
message ID, event sequence, current surface fence, focus token/revision, and
local expiry. Publishing a later focus event revokes every older unconsumed
focus-event target. The token is consumed at most once by the ordinary
`interactive.surface.select` request and can select only `focusedRegion`.
This capability-token lookup is the exact event-to-command correlation; the
client cannot supply or modify focus metadata in the selection request.

Selection continues through the one proven replacement exchange: client input
reset, correlated `interactive.surface.select/selected`, discontinuity,
configuration, visibly rendered clean frame, exact surface acknowledgement,
and host-confirmed input resumption. The event lane cannot bypass any step.

When `inputPaused` is false, the event is advisory and manual mode may ignore
it. When true, the client immediately pauses its local input producer. This is
required when a currently focused-region surface loses or changes its verified
focus. The client must select the recommended current event target, explicitly
select Desktop, or end Control; silence never resumes input. The host must have
closed admission and released held state before it can publish `inputPaused:
true`.

## Failure and fallback

An expired or superseded target, stale current fence, mismatched focus binding,
unavailable Accessibility result, or unsafe geometry cannot create a crop. If
the event is advisory, the client retains its current non-focus visual surface.
If input is paused, Desktop is the universal recovery request until a separate
host-initiated fallback profile is frozen. Media bytes alone never prove that
a focus event was applied or that input resumed.
