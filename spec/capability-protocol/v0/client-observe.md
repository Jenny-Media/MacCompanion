# Client Observe Command Owner v0.1

Status: normative bundle-independent client composition profile.

## Scope

One Observe owner is bound to one authenticated client primary router and its
Observe-only sender. It owns current host-status request correlation,
conservative freshness, and privacy-limited `audit.readSelf` pagination. It has
no Act or Control sender, never starts capture, and cannot infer network route
identity from status content.

## Status

At most one `status.snapshot.request` is pending. The owner records its message
ID and monotonic start time before enqueue. A response must correlate exactly,
decode as the closed status schema, and contain the authenticated host ID.

The first response fixes the status generation for this primary connection.
Later responses must use that same generation and a strictly increasing
revision. A generation change or revision replay/regression is a protocol
failure for the connection; a reconnect creates a new owner and may establish a
new generation.

Freshness subtracts both host-reported age (`response.sentAt` minus
`observedAt`) and the entire measured request round trip from
`validForMilliseconds`. The remainder is anchored to the client monotonic clock.
The snapshot becomes stale at the exclusive deadline even while connected. An
invalidated/disconnected owner may retain the last validated snapshot for
presentation, but it is assessed as `unreachable` and preserves the original
observation time. It is never relabelled live.

A status send failure clears that pending read and publishes no fabricated
snapshot. The prior validated snapshot, if any, remains unchanged.

An automatic selected-primary liveness check uses the same correlated status
exchange but never retains or publishes its sample as user-visible Observe
status. If a manual refresh arrives while that check is pending, the owner may
reserve one local manual intent. It sends no second wire request until the
router commits the valid correlated liveness reply. The manual request then
receives its own message ID and monotonic start time; only its own validated
reply can update user-visible status. Another manual intent or automatic check
cannot overtake the reservation. There is no unbounded queue.
The local reservation expires after at most ten seconds without a committed
liveness reply. Expiration fails the manual attempt without sending it or
turning any cached sample live; it does not cancel the independent heartbeat.

Cancellation discards the reserved intent without canceling the independent
liveness check. Invalidation, connection replacement, failed liveness send or
rejected reply fails the waiter and cannot send a late manual request. A
correlated liveness error releases the local reservation for a separate manual
attempt; it does not turn the liveness error into user-visible status. Normal
request deadlines, correlation, replay, host identity and freshness checks stay
in force. The indexed `client-observe-liveness-priority-v0.1.json` fixture records
these local scheduling rules.

## Self-audit

At most one `audit.list.request` is pending. Pagination delegates to
`ClientAuditPagerV1`: the exclusive continuation cursor, descending event
sequence, retention boundary, pruned-through marker, and dropped-event count
remain explicit. Pages are published individually and are never accumulated
into an unbounded in-memory history.

A correlated bounded error invalidates the current audit pagination attempt and
publishes only its stable code, retry class, and safe registered arguments. A
send failure likewise invalidates that attempt. Explicit reset is required
before starting a fresh audit traversal.

## Router composition and invalidation

`status.snapshot.response`, `audit.list.response`, and correlated `error` are
the only accepted reply kinds. An error is assigned to status or audit by its
exact pending correlation ID. Wrong correlation, wrong host, wrong kind,
generation/revision rollback, invalid freshness clocks, cursor violation, or
body decode failure invalidates the Observe owner and therefore the primary
router.

The owner prepares a typed status, audit-page, or bounded-error event. Only the
primary router may commit it after confirming that connection replacement or
invalidation did not win the asynchronous decode race. The Network primary
router bridge constructs this owner from the router's Observe-bound sender
before authenticated product traffic becomes ready.
