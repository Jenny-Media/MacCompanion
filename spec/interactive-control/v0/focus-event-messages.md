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

The host focus observer runs only while the locally approved Control descriptor
contains both `keyboard` and `text` and the exact authenticated primary event
sink remains active. Automatic Smart Zoom preference does not gate observation:
Type Text consumes the same privacy-filtered candidate while automatic surface
selection remains off. Removing Text authority, losing the primary sink, or
ending Control stops sampling and invalidates every unpublished or unconsumed
focus token.

`focusedRegion` requires a non-null token and focus plus
`reason: "verifiedFocus"`. Desktop requires both to be null and a non-verified
reason. Relative validity is materialized against the receiving client's
monotonic clock; host wall or monotonic focus timestamps never cross devices.

## Selection correlation and authority

An event does not select, acknowledge, or activate a surface. A focused-region
`targetToken` is random, session-scoped, bound server-side to the current
surface fence, focus token/revision, one or more consecutive refresh event
message IDs and sequences for that unchanged binding, and local expiry. The
token is consumed at most once by the ordinary `interactive.surface.select`
request and can select only `focusedRegion`. This capability-token lookup is
the exact event-to-command correlation; the client cannot supply or modify
focus metadata in the selection request.

Because focus targets are deliberately short-lived, the host may publish a
new event for an unchanged privacy-filtered focus before the previous event's
relative validity expires. It must use the next event message ID and sequence,
but it preserves the same still-unconsumed one-use target token and atomically
extends that binding's local expiry. This prevents a refresh from invalidating
a selection already being prepared from the same surface and focus fence.
A changed sanitized focus projection or changed current-surface fence revokes
the prior unconsumed binding and issues a fresh target token. If a previously
published focus returns to the already acknowledged Desktop, one Desktop
recommendation clears that stale focused candidate even though no surface
replacement is otherwise required.

The active surface descriptor's relative wire validity is an admission-
freshness bound, not the continuing execution authority. After the surface has
been acknowledged, focus publication validates the exact active surface fence
and the current renewed execution lease. It must not end an otherwise current
Control session merely because the descriptor's original transport-freshness
interval elapsed.

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

The primary event and reliable input sockets have no cross-socket ordering.
After the host has successfully released input for a focus pause, already-sent
input may still arrive before the client receives `inputPaused`. The menu may
consume its exact next reliable sequence without any OS effect, under the
still-current unexpired lease and exact session/epoch/surface/coordinate/focus
fence and allowed interaction class. This is delivery bookkeeping, not input
execution or resumption. Wrong fences, expired leases, disallowed classes,
duplicate conflicts and sequence gaps remain errors. Only the normal new
surface acknowledgement can reopen input; no drained action is replayed later.

## Failure and fallback

An expired or superseded target, stale current fence, mismatched focus binding,
unavailable Accessibility result, or unsafe geometry cannot create a crop. A
menu-side focus observation must have a positive Accessibility process ID.
While the current visual surface is one application or window, that process
must equal the locally retained owner of the selected capture target. A
focused-region surface derived from an application or window retains the same
owner check. Desktop and Desktop-derived focused regions can observe any
positive local process ID. The process ID stays in the menu process; it is
never serialized in a focus event or used as a grant. A cross-application
modal, missing process ID, or changed owner produces a Desktop recommendation
with no focus token or crop, even if its rectangle lies inside the selected
surface. The authoritative local decision cases are indexed in
`spec/fixtures/manifest.json`.
A focus sample or publication prepared from a surface/primary snapshot that
became stale while an asynchronous local operation was in flight is discarded
without ending the newer current session. Failure to publish on the still-
current authenticated primary event sink remains terminal because delivery is
then ambiguous. If the event is advisory, the client retains its current non-
focus visual surface. If input is paused, Desktop is the universal recovery
request until a separate host-initiated fallback profile is frozen. Media bytes
alone never prove that a focus event was applied or that input resumed.
