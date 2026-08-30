# Interactive Control surface-control messages v0.1

## Cross-channel delivery order

Selection pauses input, not the already-authorized old media stream. While
awaiting `selected`, the client continues validating old-fence records. A
`selected` response that overtakes those records waits at most two seconds for
its exact `mediaSequenceBeforeTransition` boundary before normal descriptor
validation. It cannot skip missing records or lower that boundary.

Conversely, the media consumer may hold only its current bounded record for at
most two seconds if a replacement record arrives before `selected`; it cannot
decode or display that record until the confirmed descriptor admits it. The
primary reader remains independent so it can supply the response. Timeout,
cancellation, invalidation, and mismatched fences remain failures. No new queue,
wire field, approval, or authority is introduced by this ordering tolerance.

A delayed render receipt for the exact prior descriptor and an already-admitted
media sequence is ignored during replacement. It cannot acknowledge the new
surface. Other receipt mismatches continue to fail validation.

Status: normative closed JSON schemas for the authenticated application-primary command channel. These messages carry no pixels, OS process/window identifiers, Accessibility objects, or durable application permission.

## Exchange and envelope rules

Surface control uses the ordinary seven-field capability-protocol envelope and its 65,536-byte strict-JSON bound. `interactive.surface.select` and `interactive.surface.ack` are original requests with null `correlationID`. `interactive.surface.selected` and `interactive.surface.acknowledged` are direct replies and correlate to the request message ID. They are admitted only after application authentication and only for the authenticated device's one active Interactive Control session.

Each request contains a positive safe-integer `sequence` that advances exactly once within the Interactive surface-control direction for that primary connection. Each reply contains an independently advancing positive safe-integer server `sequence`. A duplicate, gap, rollback, unknown field, unsafe integer, stale session/epoch/revision, or unexpected reply closes the Interactive session. Envelope message-ID replay protection remains mandatory and is not replaced by these sequences.

The privacy-limited App/Window picker consumes these same sequences through the
closed exchange in `target-inventory-messages.md`. A selection cannot race an
unresolved inventory request.

The exchange for a requested replacement is:

1. Client sends `interactive.surface.select` under the current acknowledged surface fence.
2. Agent resolves the opaque target and optional opaque Desktop display, advances surface and coordinate revisions exactly once, issues a replacement menu-runtime lease, and obtains exact preparation proof that input was released and the new capture source is prepared.
3. Host replies with `interactive.surface.selected`, including an opaque transition ID, the wire descriptor, and the last accepted media sequence before the transition.
4. Client admits an exact new-fence discontinuity, decoder configuration, and clean random-access frame. Only then may it send `interactive.surface.ack` with the same transition/fence and the clean frame's media sequence.
5. Agent and menu runtime validate the exact transition, replacement lease, full surface/focus fence, and ready sequence before returning `interactive.surface.acknowledged`. Input remains paused until that reply is validated locally and the client input producer activates the same descriptor.

Any ambiguous Agent/menu-runtime result ends the Interactive session. No network retry can infer that input resumed.

## `interactive.surface.select`

The body has exactly these fields:

- `interactiveSessionID`: canonical UUID.
- `authorizationEpoch`: positive safe integer matching the authenticated principal and active session.
- `currentSurfaceID`: current acknowledged session-scoped surface UUID.
- `expectedSurfaceRevision`: positive safe integer.
- `expectedCoordinateSpaceRevision`: positive safe integer.
- `targetKind`: one of `desktop`, `application`, `window`, or `focusedRegion`.
- `targetToken`: null for Desktop; otherwise a canonical, session-scoped opaque candidate UUID issued by the host. It is never an OS identifier.
- `targetDisplayID`: a canonical opaque display UUID only when switching to a Desktop on another currently online display; otherwise null. It is never a platform display identifier.
- `sequence`: positive safe integer.

The host resolves `targetToken` and `targetDisplayID` inside the active session and rechecks availability and privacy classification immediately before preparation. A token cannot select another session, expand interaction classes, or carry a client-supplied descriptor. A display switch is the same fail-closed replacement exchange as any other surface switch: old input is reset, the execution lease binds the newly selected display, and input resumes only after the client acknowledges a clean frame under the new surface and coordinate revisions.

## Cross-device wire descriptor

The `interactive.surface.selected` body contains exactly `transitionID`, `descriptor`, `mediaSequenceBeforeTransition`, and `sequence`.

`transitionID` is a canonical opaque UUID bound to the Agent's exact replacement command. `mediaSequenceBeforeTransition` is a nonnegative safe integer and the next media record must be exactly one greater. `sequence` is the positive server sequence.

`descriptor` is the network projection of `AdaptiveSurfaceDescriptor` and contains exactly:

- the session, authorization epoch, surface ID/kind, surface revision, and coordinate-space revision;
- nullable session-scoped application, window, parent-surface, and fallback-surface tokens;
- encoded width/height, logical point width/height, and closed rotation;
- sorted unique interaction classes and metadata fields;
- the closed privacy profile and nullable focus projection; and
- `validForMilliseconds`, an integer from 1 through 10,000.

The focus projection, when present, contains exactly its opaque token, positive revision, closed category, normalized rectangle, `editable`, and `secure`. The rectangle uses the same bounded UInt16 normalized coordinate profile as the shared surface model.

Host-local `createdAtMonotonicMilliseconds` and `expiresAtMonotonicMilliseconds` never cross the network. They are meaningful only within one boot and one machine. The client materializes its local descriptor at receipt time with `createdAt = clientMonotonicNow` and `expiresAt = createdAt + validForMilliseconds`, rejecting overflow or a descriptor already unusable at admission. Relative validity is freshness, not authorization; every later command still requires the live session, epoch, transition, and revision fences.

After awaiting local target inventory or resolution, the Agent samples its
host monotonic clock again. It validates returned creation/expiry timestamps
against that sample, not the earlier network-request timestamp. Replacement
preparation uses milliseconds and nanoseconds from the same sample; reply
validity is recomputed after runtime preparation completes. Samples must not
move backwards. Future-created or expired results remain invalid; descriptor,
lease, and session lifetimes are never extended to compensate for IPC delay.

Once the initial or replacement surface is visibly rendered and acknowledged,
an authority path that separately validates the current renewed execution lease
uses the active descriptor as the exact acknowledged surface fence rather than
reapplying its original transport-freshness interval. Focus publication and a
later replacement follow that rule. A newly resolved replacement descriptor
must still be fresh when prepared and acknowledged. This separation prevents
descriptor transport freshness from silently defeating same-surface lease
renewal without weakening authority paths that do not compose the lease.

The descriptor must satisfy the complete kind/privacy/metadata/focus rules in `client-admission.md` and `adaptive-remote-surfaces.md`. Its interaction classes must be a subset of the approved session effects and exactly match the Agent-issued replacement lease.

## `interactive.surface.ack`

The request body has exactly:

- `interactiveSessionID`, `authorizationEpoch`, `transitionID`, `surfaceID`, `surfaceRevision`, and `coordinateSpaceRevision` matching `interactive.surface.selected`;
- nullable `focusToken` and `focusRevision`, either both absent/null or both present; a descriptor with focus requires their exact values;
- `readyMediaSequence`, a positive safe integer identifying the admitted clean frame; and
- the positive client `sequence`.

The host rejects an acknowledgement before the runtime has recorded that exact clean-frame sequence, for a different/old transition, without the focused-region fence, or after lease/session expiry. The acknowledgement cannot renew a lease or select a surface.

## `interactive.surface.acknowledged`

The response repeats the exact session, epoch, transition, surface, coordinate, focus, and ready-media fields from the request, adds `inputResumed: true`, and carries the next positive server `sequence`. A false or missing `inputResumed`, any changed binding, or unexpected correlation is terminal. The client activates input only after this complete reply validates.

## Initial Desktop and fallback

The first Desktop descriptor uses the same wire projection and clean-media gate,
but its publication/acknowledgement command is not overloaded onto replacement
`transitionID`. Its separate exchange is frozen in
`initial-surface-activation.md`.

Host-initiated fallback uses the same replacement preparation and
acknowledgement invariants. The ordered focus-event lane does not itself
perform fallback; v0.1 does not infer fallback completion from events or media.

Privacy-limited focus candidates now use the separately ordered event lane in
`focus-event-messages.md`. Its one-use target token feeds this ordinary
client-requested replacement exchange; the event itself never selects a
surface or resumes input. Host-initiated fallback remains a separate future
profile and is not inferred from focus events or media.
